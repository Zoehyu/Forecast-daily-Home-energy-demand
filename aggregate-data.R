require(easyr)
require(lubridate)
begin()

dt = read.any('energydata_complete.csv') %>%
  mutate(
    odate = date,
    time = parse_date_time(odate, 'ymd_HMS'),
    date = as.Date(time), 
    hour = hour(time),
    weekday = weekdays(time),
    weekday_sunday1 = wday(time), 
    is_weekend = weekdays(time) %in% c('Saturday', 'Sunday') * 1,
    is_8a_10p = (hour >= 8 & hour <= 22) * 1,
    is_am = (hour < 12) * 1
  ) 

hourly = dt %>%
  group_by(
    date, hour, weekday, weekday_sunday1, is_weekend, is_8a_10p, is_am
  ) %>%
  summarize(
    y = sum(Appliances),
    lights = sum(lights),
    out_temperature = mean(T_out),
    maxtemp = max(T_out),
    mintemp = min(T_out),
    out_pressure = mean(Press_mm_hg),
    out_humidity = mean(RH_out),
    windspeed = mean(Windspeed),
    visibility = mean(Visibility),
    dewpoint = mean(Tdewpoint)
  )

w(hourly, 'hourly')

daily =  dt %>%
  group_by(
    date, weekday, weekday_sunday1, is_weekend
  ) %>%
  summarize(
    y = sum(Appliances),
    lights = sum(lights),
    out_temperature = mean(T_out),
    maxtemp = max(T_out),
    mintemp = min(T_out),
    out_pressure = mean(Press_mm_hg),
    out_humidity = mean(RH_out),
    windspeed = mean(Windspeed),
    visibility = mean(Visibility),
    dewpoint = mean(Tdewpoint)
  )

# first and last days are incomplete. 
daily = daily[-c(1, nrow(daily)), ]

w(daily, 'daily')
