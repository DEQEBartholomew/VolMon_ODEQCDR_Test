library(dplyr)
library(lutz)
library(odeqcdr)
library(writexl)
library(lubridate)
library(tibble)
library(tidyverse)
library(remotes)

#remotes::install_github(repo = "OR-Dept-Environmental-Quality/odeqmloctools", 
                        #host = "https://api.github.com", 
                        #dependencies = TRUE, force = TRUE, upgrade = "never")

########LB 8/11/2026 commenting out loctools, not needed for volmon script ***Confirm after output**** ##################


#Analyst Name
analyst <- "LizB"

setwd("//deqlab1/Vol_Data/WallaWalla/2025/R")

xlsx_input <- "WorkingCopy_WWBWC_HydroMon_2025.xlsx"


output_dir <-"//deqlab1/Vol_Data/WallaWalla/2025/R"

xlsx_pre_check_output <- "WallawallaHydro2025_PRECHECK.xlsx"
shiny_output <- "Wallawallahydro2025_SHINY_CDR.Rdata"
xlsx_output <- "Wallawallahydro2025_output.xlsx"

#changelog output
changelog <-  'Wallawallahydro2025_changelog'

source("//deqlab1/Vol_Data/WallaWalla/2025/R/R Scripts/cols_audit_volmon.R")
source("//deqlab1/Vol_Data/WallaWalla/2025/R/R Scripts/cols_deploy_volmon.R")
source("//deqlab1/Vol_Data/WallaWalla/2025/R/R Scripts/cols_deploy_volmon_export.R")
source("//deqlab1/Vol_Data/WallaWalla/2025/R/R Scripts/cols_deploy_volmon_forexport.R")
source("//deqlab1/Vol_Data/WallaWalla/2025/R/R Scripts/cols_prepost_volmon.R")
source("//deqlab1/Vol_Data/WallaWalla/2025/R/R Scripts/cols_projects_volmon.R")
source("//deqlab1/Vol_Data/WallaWalla/2025/R/R Scripts/contin_export_volmon_v2_1.R")
source("//deqlab1/Vol_Data/WallaWalla/2025/R/R Scripts/contin_import_volmon_v2.R")
source("//deqlab1/Vol_Data/WallaWalla/2025/R/R Scripts/mloc_col_names_volmon.R")
source("//deqlab1/Vol_Data/WallaWalla/2025/R/R Scripts/update_deploy_volmon.R")


#- Import the Data -------------------------------------------------------------

df0 <- contin_import_volmon_v2(file=xlsx_input)

df0.projects <- df0[["Projects"]]|>
  rename_with(~ str_remove_all(.x, "[\\^\\*]")) #These lines remove the ^ and * from the new template's column headers, so the script will run correctly

df0.org <- df0[["Organization_Details"]]|>
  rename_with(~ str_remove_all(.x, "[\\^\\*]"))

df0.mloc <- df0[["Monitoring_Locations"]]|>
  rename_with(~ str_remove_all(.x, "[\\^\\*]"))

df0.results <- df0[["Results"]]|>
  rename_with(~ str_remove_all(.x, "[\\^\\*]"))

df0.audits <- df0[["Audit_Data"]]|>
  rename_with(~ str_remove_all(.x, "[\\^\\*]"))

df0.deployment <- df0[["Deployment"]]|>
  rename_with(~ str_remove_all(.x, "[\\^\\*]"))

df0.prepost <- df0[["PrePost"]]|>
  rename_with(~ str_remove_all(.x, "[\\^\\*]"))

#- Completeness Pre checks -----------------------------------------------------
# A TRUE result means something is missing
checks_df <- odeqcdr::pre_checks(template_list = df0)

# Save pre check results to xlsx
writexl::write_xlsx(checks_df, path=paste0(output_dir, "/", xlsx_pre_check_output),
                    format_headers=TRUE)

#- Row numbers for indexing ----------------------------------------------------
df1.results <- dplyr::mutate(df0.results, row.results=dplyr::row_number())
df1.audits <- dplyr::mutate(df0.audits, row.audits=dplyr::row_number())
df1.deployment <- dplyr::mutate(df0.deployment, row.deployment=dplyr::row_number())
df1.prepost <- dplyr::mutate(df0.prepost, row.prepost=dplyr::row_number())

# Keep a record of the original units
# This is to convert the units back to the original after grading.
# Only needed for Results worksheet
df1.results.units <- dplyr::select(df1.results, row.results, Result.Unit.orig=Result.Unit)

# #- Set Project ID --------------------------------------------------------------

df1.projects <- df0.projects %>% add_column(Project.ID="ODEQVolMonWQProgram")

#- Review Monitoring Location Info----------------------------------------------

# df1.mloc <- odeqcdr::launch_map(mloc=df0.mloc)

# Make manual changes to the xlsx spreadsheet and re import if needed:
# df1.mloc <- odeqcdr::contin_import(file=xlsx_input, sheets=c("Monitoring_Locations"))[["Monitoring_Locations"]]

# # Make sure there are no duplicate entries.

df1.mloc <- dplyr::distinct(df0.mloc)


# Save R global environment just in case.
save.image(paste0(output_dir, "/Renv.RData"))

#- Update Monitoring Location ID Name-------------------------------------------

# # Fix monitoring location IDs w/ invalid characters
# # The following are invalid characters in Monitoring Location IDs
# # ` ~ ! # $ % ^ & * ( ) [ { ] } \ | ; ' " < > / ? [space]
# # @ is replaced with 'at'
# # The rest are replaced with '_'
# df1.mloc$Monitoring.Location.ID <- odeqcdr::inchars(x=df1.mloc$Monitoring.Location.ID)
# df1.deployment$Monitoring.Location.ID <- odeqcdr::inchars(x=df1.deployment$Monitoring.Location.ID)
# df1.results$Monitoring.Location.ID <- odeqcdr::inchars(x=df1.results$Monitoring.Location.ID)
# df1.audits$Monitoring.Location.ID <- odeqcdr::inchars(x=df1.audits$Monitoring.Location.ID)

#- Check if the correct timezone is used ---------------------------------------
# Check that monitoring stations located in the Pacific time zone have pacific time
# zones (e.g. PST/PDT) and stations in the Mountain time zone have mountain time
# zones (e.g. MST/MDT). This is checked by adding the Olson name
# timezone (see OlsonNames()) based on the monitoring location latitude and longitude.
# Make sure the latitude and longitude are correct before running this code.
# The Olson name timezone is used in dt_combine() and dst_check()

df.tz <- df1.mloc %>%
  dplyr::select(Monitoring.Location.ID, Latitude, Longitude) %>%
  dplyr::distinct() %>%
  dplyr::mutate(tz_name=lutz::tz_lookup_coords(lat=Latitude,lon=Longitude, method="accurate", warn=FALSE)) %>%
  dplyr::select(-Latitude, -Longitude)

df1.deployment <- dplyr::left_join(df1.deployment, df.tz, by="Monitoring.Location.ID") %>% add_column(Project.ID="ODEQVolMonWQProgram")
df1.results <- dplyr::left_join(df1.results, df.tz, by="Monitoring.Location.ID")
df1.audits <- dplyr::left_join(df1.audits, df.tz, by="Monitoring.Location.ID")

# Add a timezone if one is missing, The code will correct in dst_check if it's wrong.
# Flag timezones that are wrong.
df1.results <- df1.results %>%
  dplyr::mutate(Activity.Start.End.Time.Zone=dplyr::case_when(tz_name=="America/Los_Angeles" &
                                                                is.na(Activity.Start.End.Time.Zone) ~ "PDT",
                                                              tz_name=="America/Boise" &
                                                                is.na(Activity.Start.End.Time.Zone) ~ "MDT",
                                                              TRUE ~ Activity.Start.End.Time.Zone),
                tz_wrong=dplyr::case_when(tz_name=="America/Los_Angeles" &
                                            Activity.Start.End.Time.Zone %in% c("PDT", "PST") ~ FALSE,
                                          tz_name=="America/Boise" &
                                            Activity.Start.End.Time.Zone %in% c("MDT", "MST") ~ FALSE,
                                          TRUE ~ TRUE))

df1.audits <- df1.audits %>%
  dplyr::mutate(Activity.Start.End.Time.Zone=dplyr::case_when(tz_name=="America/Los_Angeles" &
                                                                is.na(Activity.Start.End.Time.Zone) ~ "PDT",
                                                              tz_name=="America/Boise" &
                                                                is.na(Activity.Start.End.Time.Zone) ~  "MDT",
                                                              TRUE ~ Activity.Start.End.Time.Zone),
                tz_wrong=dplyr::case_when(tz_name=="America/Los_Angeles" &
                                            Activity.Start.End.Time.Zone %in% c("PDT", "PST") ~ FALSE,
                                          tz_name=="America/Boise" &
                                            Activity.Start.End.Time.Zone %in% c("MDT", "MST") ~ FALSE,
                                          TRUE ~ TRUE))

# # Show which rows failed the tz check (tz_wrong=TRUE)
# df1.results[df1.results$tz_wrong, c("row.results")]
# df1.audits[df1.audits$tz_wrong, c("row.audits")]

# check and correct for DST ----------------------------------------------------
# dst_check() checks that date and time conform to changes between
# Daylight Time and Standard Time. The output is an updated PoSIXct datetime.
# This also runs dt_combine(). Time change corrections will be identified by stations and periods.
# Any changes should be manually reviewed.

df1.results$datetime <- odeqcdr::dst_check(df=df1.results,
                                           tz_col="tz_name")

df1.audits$audit.datetime.start <- odeqcdr::dst_check(df=df1.audits,
                                                      date_col="Activity.Start.Date",
                                                      time_col="Activity.Start.Time",
                                                      tz_col="tz_name")

df1.audits$audit.datetime.end  <- odeqcdr::dst_check(df=df1.audits,
                                                     date_col="Activity.End.Date",
                                                     time_col="Activity.End.Time",
                                                     tz_col="tz_name")

#- Combine Deployment date and time --------------------------------------------
# No need to check for dst.

df1.deployment$Deployment.Start.Date <- odeqcdr::dt_combine(df=df1.deployment,
                                                            date_col = "Deployment.Start.Date",
                                                            time_val = "00:00:00",
                                                            tz_col="tz_name")

df1.deployment$Deployment.End.Date <- odeqcdr::dt_combine(df=df1.deployment,
                                                          date_col = "Deployment.End.Date",
                                                          time_val = "23:59:00",
                                                          tz_col="tz_name")

#- Apply any corrections back to date and time columns Adds Comments -----------

df2.results <- odeqcdr::dt_parts(df=df1.results)

df2.audits <- odeqcdr::dt_parts(df=df1.audits,
                                datetime_col="audit.datetime.start",
                                date_col="Activity.Start.Date",
                                time_col="Activity.Start.Time")

df2.audits <- odeqcdr::dt_parts(df=df1.audits,
                                datetime_col="audit.datetime.end",
                                date_col="Activity.End.Date",
                                time_col="Activity.End.Time")

#- Convert Units ---------------------------------------------------------------
# This converts the result value and changes the Unit column.
# This is needed for grading and anomaly checking
# This converts any
# deg F -> deg C
# ug/l -> mg/l
# Add others as needed.

df3.audits <- df2.audits %>%
  dplyr::mutate(Result.Value=dplyr::case_when(Result.Unit=="deg F" ~ (Result.Value - 32) * (5 / 9),
                                              Result.Unit=="ug/l" ~ Result.Value * 0.001,
                                              TRUE ~ Result.Value),
                Result.Unit=dplyr::case_when(Result.Unit=="deg F" ~ "deg C",
                                             Result.Unit=="ug/l" ~ "mg/l",
                                             TRUE ~ Result.Unit)) %>%
  add_column(precDQL=NA,rDQL=NA,Project.ID=NA)

df3.prepost <- df1.prepost  %>%
  dplyr::mutate(Equipment.Result.Value=dplyr::case_when(Equipment.Result.Unit=="deg F" ~ (Equipment.Result.Value - 32) * (5 / 9),
                                                        Equipment.Result.Unit=="ug/l" ~ Equipment.Result.Value * 0.001,
                                                        TRUE ~ Equipment.Result.Value),
                Equipment.Result.Unit=dplyr::case_when(Equipment.Result.Unit=="deg F" ~ "deg C",
                                                       Equipment.Result.Unit=="ug/l" ~ "mg/l",
                                                       TRUE ~ Equipment.Result.Unit),
                Reference.Result.Value=dplyr::case_when(Reference.Result.Unit=="deg F" ~ (Reference.Result.Value - 32) * (5 / 9),
                                                        Reference.Result.Unit=="ug/l" ~ Reference.Result.Value * 0.001,
                                                        TRUE ~Reference.Result.Value),
                Reference.Result.Unit=dplyr::case_when(Reference.Result.Unit=="deg F" ~ "deg C",
                                                       Reference.Result.Unit=="ug/l" ~ "mg/l",
                                                       TRUE ~  Reference.Result.Unit))

df3.results <- df2.results %>%
  dplyr::mutate(Result.Value=dplyr::case_when(Result.Unit=="deg F" ~ (Result.Value - 32) * (5 / 9),
                                              Result.Unit=="ug/l" ~ Result.Value * 0.001,
                                              TRUE ~ Result.Value),
                Result.Unit=dplyr::case_when(Result.Unit=="deg F" ~ "deg C",
                                             Result.Unit=="ug/l" ~ "mg/l",
                                             TRUE ~ Result.Unit)) %>%
  add_column(Result.Comment=NA,Project.ID=NA)

#- Grade PrePost ---------------------------------------------------------------

df3.results$accDQL <- odeqcdr::dql_accuracy(prepost=df3.prepost, results=df3.results)

#- Grade Audits ----------------------------------------------------------------

df3.results$precDQL <- dql_precision(audits=df3.audits, results=df3.results, deployment=df1.deployment)
df3.audits.dql <- dql_precision(audits=df3.audits, results=df3.results, deployment=df1.deployment,
                                audits_only = TRUE)
#- Final DQL -------------------------------------------------------------------

# Set up final grade column to be verified using shiny app and further review
# Update the rDQL when the submitted result status == "Rejected"
# Automatically set Result.Status.ID = "Rejected" when results are outside of deployment period
df4.results <- df3.results %>%
  dplyr::left_join(df1.deployment[,c("Monitoring.Location.ID", "Equipment.ID",
                                     "Characteristic.Name", "Deployment.Start.Date",
                                     "Deployment.End.Date")],
                   by=c("Monitoring.Location.ID", "Equipment.ID", "Characteristic.Name")) %>%
  dplyr::mutate(deployed=dplyr::if_else(datetime >= Deployment.Start.Date &
                                          datetime <= Deployment.End.Date, TRUE, FALSE),
                Result.Status.ID=dplyr::case_when(!deployed ~ "Rejected",
                                                  TRUE ~ Result.Status.ID),
                rDQL=dplyr::case_when(precDQL == 'C' | accDQL== 'C' ~ 'C',
                                      precDQL == 'B' | accDQL== 'B' ~ 'B',
                                      precDQL == 'A' & accDQL== 'A' ~ 'A',
                                      precDQL == 'E' & accDQL== 'E' ~ 'E',
                                      TRUE ~ 'B'),
                rDQL=dplyr::if_else(Result.Status.ID == "Rejected","C",rDQL)) %>%
  dplyr::select(-Deployment.Start.Date, -Deployment.End.Date) %>%
  dplyr::arrange(row.results) %>%
  as.data.frame()

# #- Anomalies -------------------------------------------------------------------
# Flag potential anomalies
# Anomaly = TRUE if one of the daily summary statistics deviate from the typical range.

# First add Stream Order
df5.results <- df4.results %>%
  dplyr::left_join(df1.mloc[,c("Monitoring.Location.ID", "Reachcode", "Permanent.Identifier")], by="Monitoring.Location.ID") %>%
  dplyr::left_join(odeqmloctools::ornhd[,c("StreamOrder", "Permanent_Identifier")], by=c("Permanent.Identifier"="Permanent_Identifier")) #LB Updated from
#ODEQCDR to odeqmloctools

###############LB 5/4/2026 trying to change delta flagging in Shiny to visualize DQLs############################

# Get a dataframe of just the anomaly stats
# Run anomaly check (unchanged)

df5.results.anom <- odeqcdr::anomaly_check(results = df5.results,deployment = df1.deployment,return_df = TRUE)



# 1. Clamp delta_per_hour so it doesn't dominate (but still plots)
df5.results.anom <- df5.results.anom %>%
  dplyr::mutate(delta_per_hour = pmin(pmax(delta_per_hour, -5), 5))

# 2. Rebuild Anomaly WITHOUT delta_per_hour influence
df5.results.anom <- df5.results.anom %>%
  dplyr::mutate(Anomaly = ifelse(daily_min_q10 | daily_max_q90 | daily_mean_q10 | daily_mean_q90,
                                 "TRUE","FALSE"))

# 3. Force correct factor levels so Shiny color scales work
df5.results.anom$Anomaly <- factor(
  df5.results.anom$Anomaly,levels = c("TRUE", "FALSE"))


df5.results.2review <- df5.results.anom %>%
  dplyr::select(row.results,Anomaly,dt_shift,delta_per_hour,daily_min_q10,daily_max_q90,daily_mean_q10,daily_mean_q90) %>%
  dplyr::right_join(df5.results)


# list to export to Shiny
shiny_list <-list(Deployment=df1.deployment,
                  Audit_Stats=df3.audits.dql,
                  Results_Anom=df5.results.anom)

save(shiny_list, file=shiny_output)

# Launch Shiny app for further review.
odeqcdr::launch_shiny()

#- Make DQL and Status edits based on Shiny Review------------------------------
# Updates Result Status ID also
# This section should be structured like this:

# #######################################################################################################################
# #######################################################################################################################
# 
#

df5.results <- df4.results %>%
  
  #'[32807-ORDEQ - 21778952 - Temperature, water]: 1:14210
  #LB no changes. Audits look good. 
  
  #'[32809-ORDEQ - 21779080 - Temperature, water]: 14211:28426
  #LB no changes. Audits look good. 
  
  #'[32808-ORDEQ - 21152155 - Temperature, water]: 28427:42641
  odeqcdr::dql_update(rows = c(28427:28430), "C", "Before deployment audit") %>% #LB 
  
  #'[32007-ORDEQ - 21973821 - Temperature, water]: 42642:56863
  odeqcdr::dql_update(rows = c(42642:42650), "C", "Before deployment audit") %>% #LB 
  
  #'[32800-ORDEQ - 21057272 - Temperature, water]: 56864:71076
  odeqcdr::dql_update(rows = c(62422:67522), "A", "") %>% #LB formerly B data. Corrected 8/20 audit score. 
  odeqcdr::dql_update(rows = c(62421, 64927), "C", "Logger not equilibrated") %>% #LB
  odeqcdr::dql_update(rows = c(68541:68639, 69370:70001), "C", "Logger out of water") %>% #LB note in data about logger being out of water/site 
  #going dry 9/27-28 and 10/05-10/11
  odeqcdr::dql_update(rows = c(56864:56873), "C", "Before deployment audit") %>% #LB 
  
  #'[41577-ORDEQ - 21779078 - Temperature, water]: 71077:85287
  odeqcdr::dql_update(rows = c(71077:71078), "C", "Before deployment audit") %>% #LB 
  
  #'[41576-ORDEQ - 21152036 - Temperature, water]: 85288:99500
  odeqcdr::dql_update(rows = c(85288:85289), "C", "Before deployment audit") %>% #LB 
  
  #'[32803-ORDEQ - 21057267 - Temperature, water]: 99501:113712
  #LB no changes. Audits look good. 
  
  #'[23492-ORDEQ - 21530903 - Temperature, water]: 113713:127930
  odeqcdr::dql_update(rows = c(113713:113718), "C", "Before deployment audit") %>% #LB 
  
  #'[32810-ORDEQ - 21781954 - Temperature, water]: 127931:142149
  odeqcdr::dql_update(rows = c(127931:127937), "C", "Before deployment audit") %>% #LB 
  
  #'[40757-ORDEQ - 21975871 - Temperature, water]: 142150:156362
  odeqcdr::dql_update(rows = c(142150:142151), "C", "Before deployment audit") %>% #LB 
  
  #'[23493-ORDEQ - 21975874 - Temperature, water]: 156363:170587
  odeqcdr::dql_update(rows = c(156363:156373), "C", "Before deployment audit") %>% #LB 
  
  #'[32799-ORDEQ - 21779079 - Temperature, water]: 170588:184800
  odeqcdr::dql_update(rows = c(170588:170598), "C", "Before deployment audit") %>% #LB
  
  #'[40722-ORDEQ - 21057264 - Temperature, water]: 184801:193910
  odeqcdr::dql_update(rows = c(191514:192282), "B", "Suspect diurnal patterns") %>% #LB
  odeqcdr::dql_update(rows = c(193724:193910), "E", "Data of unknown quality. Site dries by 7/26") %>% #LB
  
  #'[41556-ORDEQ - 21781955 - Temperature, water]: 193911:208121
  odeqcdr::dql_update(rows = c(194593:196595), "E", "Data of unknown quality. Site dries intermittantly 6/4-6/25") %>% #LB
  
  #'[41558-ORDEQ - 20970219 - Temperature, water]: 208122:222344
  odeqcdr::dql_update(rows = c(208122:208131), "C", "Before deployment audit") %>% #LB
  
  #'[41559-ORDEQ - 21778948 - Temperature, water]: 222345:236557
  #LB no changes. Audits look good. 
  
  #'[32804-ORDEQ - 21779081 - Temperature, water]: 236558:252781
  odeqcdr::dql_update(rows = c(239071:249108), "C", "Dry site 6/29-10/10") %>% #LB
  odeqcdr::dql_update(rows = c(249109:252781), "E", "Data of unknown quality") %>% #LB
  
  #'[41573-ORDEQ - 21781961 - Temperature, water]: 252782:269008
  odeqcdr::dql_update(rows = c(252782:252805), "C", "Before deployment audit") %>% #LB
  
  #'[41572-ORDEQ - 21975873 - Temperature, water]: 269009:285234
  odeqcdr::dql_update(rows = c(269009:269020), "C", "Before deployment audit") %>% #LB
  
  #'[41571-ORDEQ - 21057265 - Temperature, water]: 285235:301460
  odeqcdr::dql_update(rows = c(285235:285239), "C", "Before deployment audit") %>% #LB
  
  #'[42258-ORDEQ - 21057266 - Temperature, water]: 301461:317685
  #LB no changes
  
  #'[41575-ORDEQ - 20970220 - Temperature, water]: 317686:333909
  #LB diurnal patterns stop shortly after 6/15. Downgrading data to E. 
  odeqcdr::dql_update(rows = c(319109:333909), "E", "Data of unknown quality. Suspect lack of diurnal variation") %>% #LB
  
  #'[41562-ORDEQ - 21057269 - Temperature, water]: 333910:345619
  odeqcdr::dql_update(rows = c(333910), "C", "Logger not equilibrated") %>% #LB
  odeqcdr::dql_update(rows = c(333911:345619), "A", "") %>% #LB formerly B data. Upgraded audit score. 
  
  #'[41565-ORDEQ - 21057273 - Temperature, water]: 345620:357332
  odeqcdr::dql_update(rows = c(345620), "C", "Logger not equilibrated") %>% #LB
  odeqcdr::dql_update(rows = c(345621:357332), "A", "") %>% #LB formerly B data. Upgraded audit score. 
  
  #'[41563-ORDEQ - 20970216 - Temperature, water]: 357333:369041
  #LB no changes
  
  #'[42257-ORDEQ - 21975872 - Temperature, water]: 369042:380659
  odeqcdr::dql_update(rows = c(369042), "C", "Before deployment audit") %>% #LB
  
  #'[37696-ORDEQ - 21152154 - Temperature, water]: 380660:386958
  odeqcdr::dql_update(rows = c(386809:386958), "E", "Data of unknown quality. Site goes dry by 6/28") %>% #LB
  
  #'[37695-ORDEQ - 21530904 - Temperature, water]: 386959:388402 
  odeqcdr::dql_update(rows = c(386959:386960), "C", "Before deployment audit") %>% #LB
  odeqcdr::dql_update(rows = c(387718:388402 ), "E", "Data of unknown quality. Site goes dry by 5/8") #LB





df4.audits.dql <- df3.audits.dql %>%
  
  

  
  #'[32807-ORDEQ - 21778952 - Temperature, water]: 1:14210
  #LB No changes to audits
  #'[32809-ORDEQ - 21779080 - Temperature, water]: 14211:28426
  #LB No changes to audits
  #'[32808-ORDEQ - 21152155 - Temperature, water]: 28427:42641
  #LB No changes to audits
  #'[32007-ORDEQ - 21973821 - Temperature, water]: 42642:56863
  #LB No changes to audits
  #'[32800-ORDEQ - 21057272 - Temperature, water]: 56864:71076
  odeqcdr::dql_update(rows = c(46), "A", "") %>% #LB corrected 2025-08-20 10:30 PDT audit to pair with 2025-08-20 10:15 PDT. Would also
  #be A level if paired with 2025-08-20 10:45 PDT
  #'[41577-ORDEQ - 21779078 - Temperature, water]: 71077:85287  
  #LB No changes to audits
  #'[41576-ORDEQ - 21152036 - Temperature, water]: 85288:99500
  #LB No changes to audits
  #'[32803-ORDEQ - 21057267 - Temperature, water]: 99501:113712 
  #LB No changes to audits
  #'[23492-ORDEQ - 21530903 - Temperature, water]: 113713:127930'
  #LB No changes to audits
  #'[32810-ORDEQ - 21781954 - Temperature, water]: 127931:142149
  #LB No changes to audits  
  #'[40757-ORDEQ - 21975871 - Temperature, water]: 142150:156362
  #LB No changes to audits  
  #'[23493-ORDEQ - 21975874 - Temperature, water]: 156363:170587
  #LB No changes to audits 
  #'[32799-ORDEQ - 21779079 - Temperature, water]: 170588:184800
  #LB No changes to audits
  #'[40722-ORDEQ - 21057264 - Temperature, water]: 184801:193910
  #LB No changes to audits
  #'[41556-ORDEQ - 21781955 - Temperature, water]: 193911:208121 
  #LB No changes to audits
  #'[41558-ORDEQ - 20970219 - Temperature, water]: 208122:222344 
  #LB No changes to audits
  #'[41559-ORDEQ - 21778948 - Temperature, water]: 222345:236557
  #LB No changes to audits
  #'[32804-ORDEQ - 21779081 - Temperature, water]: 236558:252781  
  #LB No changes to audits. Keeping deployment audit as E. 
  #'[41573-ORDEQ - 21781961 - Temperature, water]: 252782:269008 
  odeqcdr::dql_update(rows = c(140), "B", "") %>% #LB corrected 2025-11-18 09:15 PST audit to B. >30 min but within expected range
  #'[41572-ORDEQ - 21975873 - Temperature, water]: 269009:285234
  odeqcdr::dql_update(rows = c(142), "B", "") %>% #LB corrected 2025-11-18 10:45 PST audit to B. >30 min but within expected range
  #'[41571-ORDEQ - 21057265 - Temperature, water]: 285235:301460  
  odeqcdr::dql_update(rows = c(144), "B", "") %>% #LB corrected 2025-11-18 11:30 PST audit to B. >30 min but within expected range
  #'[42258-ORDEQ - 21057266 - Temperature, water]: 301461:317685
  odeqcdr::dql_update(rows = c(146), "B", "") %>% #LB corrected 2025-11-18 12:15 PST audit to B. >30 min but within expected range
  #'[41575-ORDEQ - 20970220 - Temperature, water]: 317686:333909 
  #LB no changes to audits. Keeping E audit
  #'[41562-ORDEQ - 21057269 - Temperature, water]: 333910:345619  
  odeqcdr::dql_update(rows = c(149), "A", "") %>% #LB corrected 2025-06-30 11:15 PDT audit to pair with 2025-06-30 11:30 PDT 
  #'[41565-ORDEQ - 21057273 - Temperature, water]: 345620:357332 
  odeqcdr::dql_update(rows = c(151), "A", "") #LB corrected 2025-06-30 11:00 PDT audit to pair with 2025-06-30 11:15 PDT
  #'[41563-ORDEQ - 20970216 - Temperature, water]: 357333:369041
  #LB no changes to audits.
  #'[42257-ORDEQ - 21975872 - Temperature, water]: 369042:380659
  #LB no changes to audits.
  #'[37696-ORDEQ - 21152154 - Temperature, water]: 380660:386958  
  #LB no changes to audits.
  #'[37695-ORDEQ - 21530904 - Temperature, water]: 386959:388402 
  #LB no changes to audits.
  
  
  
  #######################################################################################################################

# If no edits are required:
#df5.results <- df4.results
#df4.audits.dql <- df3.audits.dql

#######################################################################################################################
#######################################################################################################################

#############LB added 5/4/26. Trying to create secondary shiny file that does not have all the data flagged with the delta per hour
##LB Deleted redundant script 5/7/26

df5.results.anom <- odeqcdr::anomaly_check(
  results = df5.results,deployment = df1.deployment,return_df = TRUE)


# 1. Clamp delta_per_hour so it doesn't dominate (but still plots)
df5.results.anom <- df5.results.anom %>%
  dplyr::mutate(delta_per_hour = pmin(pmax(delta_per_hour, -5), 5))

# 2. Rebuild Anomaly WITHOUT delta_per_hour influence
df5.results.anom <- df5.results.anom %>%
  dplyr::mutate(Anomaly = ifelse(daily_min_q10 | daily_max_q90 | daily_mean_q10 | daily_mean_q90,"TRUE","FALSE"))

# 3. Force correct factor levels so Shiny color scales work
df5.results.anom$Anomaly <- factor(df5.results.anom$Anomaly,
                                   levels = c("TRUE", "FALSE"))

# Prepare review dataset
df5.results.2review <- df5.results.anom |>
  dplyr::select(row.results,Anomaly,dt_shift,delta_per_hour,daily_min_q10,daily_max_q90,daily_mean_q10,daily_mean_q90) |>
  dplyr::right_join(df5.results)

# List to export to Shiny
shiny_list <- list(
  Deployment   = df1.deployment,Audit_Stats  = df4.audits.dql,   
  Results_Anom = df5.results.2review)

# Save Shiny input file (matches naming + directory behavior)
save(shiny_list,file = paste0(output_dir, "/", analyst, "_REVIEW2_SHINY_CDR.Rdata"))

# Launch Shiny app for further review
odeqcdr::launch_shiny()

####################################################################################################################

#Once that is done update status IDs
# Set status IDs
df6.results <- odeqcdr::status_update(df5.results)
df.audits.final <- odeqcdr::status_update(df4.audits.dql)

#Output changelog

#Calualte difference in the dataframes
differences <- compareDF::compare_df(df6.results, df4.results, group_col = 'row.results')

#output this file into excel
compareDF::create_output_table(differences, output_type = "xlsx", file_name = paste0(output_dir,"/", changelog,"_", analyst, ".xlsx"))


#Set DOsat grades to grades for DO concentration
df7.results <- odeqcdr::dql_dos(df6.results)


#Drop results outside deployment periods
df.results.final <- dplyr::filter(df7.results, deployed)

##### If you need to re-order... ####

# df.results.final <- df.results.final %>%
#   dplyr::arrange(Monitoring.Location.ID, Equipment.ID, Characteristic.Name,
#                  Activity.Start.Date, Activity.Start.Time)


# Generate Summary Stats -------------------------------------------------------

df.sumstats <- odeqcdr::sumstats(results=df.results.final, deployment=df1.deployment, project_id=df1.projects$Project.ID)

#- Output updated data back to xlsx template -----------------------------------

# First set the result units back to the original
# This only converts deg C -> deg F and mg/l -> ug/l
# Add others as needed. Only needed for Results worksheet.
# Round results to 3 decimals.

df.results.final <- df.results.final %>%
  dplyr::left_join(df1.results.units, by="row.results") %>%
  dplyr::mutate(Result.Value=dplyr::case_when(Result.Unit.orig=="deg F" ~ (Result.Value * (9 / 5)) + 32,
                                              Result.Unit.orig=="ug/l" ~ Result.Value * 1000,
                                              TRUE ~ Result.Value),
                Result.Unit=dplyr::case_when(Result.Unit.orig=="deg F" ~ "deg F",
                                             Result.Unit.orig=="ug/l" ~ "ug/l",
                                             TRUE ~ Result.Unit)) %>%
  dplyr::select(-Result.Unit.orig) %>%
  dplyr::arrange(row.results) %>%
  as.data.frame()

#### Update the Deployment information ####

# Add Equipment Type

df1.deployment<- df1.deployment %>% 
  add_column(Equipment.Type="Probe/Sensor")

df2.deployment <- update_deploy_volmon(deploy = df1.deployment)

# Fill in the project ID
df2.deployment$Project.ID <- df0.projects$Project.ID


# Save R global environment just in case.
save.image(paste0(output_dir, "/Renv.RData"))


#### Export####

contin_export_volmon_v2 (file=paste0(output_dir, "/", xlsx_output),
                         org=df0.org,
                         projects=df1.projects,
                         mloc=df1.mloc,
                         deployment=df1.deployment,
                         results=df.results.final,
                         prepost=df0.prepost,
                         audits=df.audits.final,
                         sumstats=df.sumstats)
