require(easyr)
begin()

require(forecast)
require(vars)
require(TSA)

dt = read.any('../hourly.csv')

t = TSA::periodogram(dt$y)

spikes = which(t$spec > 1.96 * sd(t$spec))
data.frame(
  freq = t$freq,
  spec = t$spec
) %>% 
  mutate(period = 1/freq) %>%
  arrange(desc(spec)) %>%
  head(10)
