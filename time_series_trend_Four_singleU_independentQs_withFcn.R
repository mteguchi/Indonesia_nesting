rm(list=ls())
library(jagsUI)
library(coda)
library(tidyverse)
library(loo)

data.extract <- function(location, 
                         year.begin, 
                         year.end, 
                         season.begin = year.begin, 
                         season.end = year.end){
  # In March 2019, we received new data for 2018. So, the raw data file
  # has been updated.  
  # On 16 April 2019, the last few data points for 2019 were received
  # so the data files have been updated. 
  if (is.null(season.begin)) season.begin <- year.begin
  if (is.null(season.end)) season.end <- year.end
  
  if (location == "JM"){
    data.0 <- read.csv("JM_nests_April2019.csv")
    
    data.0 %>% 
      select(Year_begin, Month_begin, JM_Nests) %>%
      mutate(Nests = JM_Nests) -> data.0
    
  } else if (location == "W"){
    data.0 <- read.csv("W_nests_April2019.csv")
    data.0 %>% 
      select(Year_begin, Month_begin, W_Nests) %>%
      mutate(Nests = W_Nests) -> data.0
  }
  
  # create regularly spaced time series:
  data.2 <- data.frame(Year = rep(min(data.0$Year_begin,
                                      na.rm = T):max(data.0$Year_begin,
                                                     na.rm = T),
                                  each = 12),
                       Month_begin = rep(1:12,
                                         max(data.0$Year_begin,
                                             na.rm = T) -
                                           min(data.0$Year_begin,
                                               na.rm = T) + 1)) %>%
    mutate(begin_date = as.Date(paste(Year,
                                      Month_begin,
                                      '01', sep = "-"),
                                format = "%Y-%m-%d"),
           Frac.Year = Year + (Month_begin-0.5)/12) %>%
    select(Year, Month_begin, begin_date, Frac.Year)
  
  # also make "nesting season" that starts April and ends March
  
  data.0 %>% mutate(begin_date = as.Date(paste(Year_begin,
                                               Month_begin,
                                               '01', sep = "-"),
                                         format = "%Y-%m-%d")) %>%
    mutate(Year = Year_begin,
           Month = Month_begin,
           f_month = as.factor(Month),
           f_year = as.factor(Year),
           Frac.Year = Year + (Month_begin-0.5)/12) %>%
    select(Year, Month, Frac.Year, begin_date, Nests) %>%
    na.omit() %>%
    right_join(.,data.2, by = "begin_date") %>%
    transmute(Year = Year.y,
              Month = Month_begin,
              Frac.Year = Frac.Year.y,
              Nests = Nests,
              Season = ifelse(Month < 4, Year-1, Year),
              Seq.Month = ifelse(Month < 4, Month + 9, Month - 3)) %>%
    reshape::sort_df(.,vars = "Frac.Year") %>%
    filter(Season >= season.begin & Season <= season.end) -> data.1
  
  data.1 %>% filter(Month > 3 & Month < 10) -> data.summer
  data.1 %>% filter(Month > 9 | Month < 4) %>%
    mutate(Seq.Month = Seq.Month - 6) -> data.winter
  
  jags.data <- list(y = log(data.1$Nests),
                    m = data.1$Seq.Month,
                    T = nrow(data.1))
  
  y <- matrix(log(data.1$Nests), ncol = 12, byrow = TRUE)
  
  jags.data2 <- list(y = y,
                     m = matrix(data.1$Seq.Month, 
                                ncol = 12, byrow = TRUE),
                     n.years = nrow(y))
  
  y.summer <- matrix(log(data.summer$Nests),
                     ncol = 6, byrow = TRUE)
  
  y.winter <- matrix(log(data.winter$Nests),
                     ncol = 6, byrow = TRUE)
  
  jags.data2.summer <- list(y = y.summer,
                            m = matrix(data.summer$Seq.Month, 
                                       ncol = 6, byrow = TRUE),
                            n.years = nrow(y.summer))
  
  jags.data2.winter <- list(y = y.winter,
                            m = matrix(data.winter$Seq.Month, 
                                       ncol = 6, byrow = TRUE),
                            n.years = nrow(y.winter))
  
  out <- list(jags.data = jags.data,
              jags.data2 = jags.data2,
              jags.data.summer = jags.data2.summer,
              jags.data.winter = jags.data2.winter,
              data.1 = data.1,
              data.summer = data.summer,
              data.winter = data.winter)
  return(out)
}


save.data <- T
save.fig <- T
run.date <- Sys.Date()

#Set up the plotting colors.

fill.color <-  "darkseagreen"
fill.color.N1 <- "blue4"
fill.color.N2 <- "gold4"
fill.color.summer <- "darksalmon"
fill.color.winter <- "gray65"
fill.alpha <-  0.65
line.color <-  "darkblue"
line.color.N <- "cadetblue"
line.color.summer <- "red3"
line.color.winter <- "greenyellow"
data.color <- "black"
data.size <- 1.5
obsd.color <- "red2"


#Set up the MCMC parameters

MCMC.params <- list(n.chains = 5,
                    n.samples = 50000,
                    n.burnin = 35000,
                    n.thin = 2)

#Bring in the data

# JM
#2001 for JM and 2006 for W to 2017
period.JM <- 12
period.W <- 6
maxN <- 10000

year.begin.JM <- 2001
year.end <- 2017
data.jags.JM <- data.extract(location = "JM", 
                             year.begin = year.begin.JM, 
                             year.end = year.end)

year.begin.W <- 2006
data.jags.W <- data.extract(location = "W", 
                            year.begin = year.begin.W, 
                            year.end = year.end)

filename.root <- paste0("SSAR1_norm_norm_trend_Four_singleU_independentQs_", run.date)


#Combine datasets for analysis
# JM has more data than W, so we need to pad W data
y.W <- rbind(array(data = NA, 
                   dim = c(nrow(data.jags.JM$jags.data2$y) - nrow(data.jags.W$jags.data2$y),
                           ncol(data.jags.JM$jags.data2$y))),
             data.jags.W$jags.data2$y)

y <- array(data= NA, 
           dim = c(nrow(data.jags.JM$jags.data2$y),
                   ncol(data.jags.JM$jags.data2$y), 2))

y[,,1] <- data.jags.JM$jags.data2$y
y[,,2] <- y.W

jags.data <- list(y = y,
                  C0 = c(15, 15),
                  n.months = 12,
                  C_cos = c(sum(apply(matrix(1:12, nrow=1), 
                                      MARGIN = 1, 
                                      FUN = function(x) cos(2 * pi * x/period.JM))), 
                            sum(apply(matrix(1:12, nrow=1), 
                                      MARGIN = 1, 
                                      FUN = function(x) cos(2 * pi * x/period.W)))),
                  C_sin = c(sum(apply(matrix(1:12, nrow=1), 
                                      MARGIN = 1, 
                                      FUN = function(x) sin(2 * pi * x/period.JM))),
                            sum(apply(matrix(1:12, nrow=1), 
                                      MARGIN = 1, 
                                      FUN = function(x) sin(2 * pi * x/period.W)))),
                  pi = pi,
                  period = c(period.JM, period.W),
                  N0_mean = c(log(sum(exp(data.jags.JM$jags.data2$y[1,]), na.rm = T)),
                              log(sum(exp(data.jags.W$jags.data2$y[1,]), na.rm = T))),
                  N0_sd = c(10, 10),
                  n.timeseries = dim(y)[3],
                  n.years = dim(y)[1])


#Define which parameters to monitor

jags.params <- c('N', 'U', "p", "p.beta.cos", "p.beta.sin",
                 "sigma.N", 'sigma.Q', "sigma.R",
                 "mu", "y", "X", "deviance", "loglik")

jm <- jags(jags.data,
           inits = NULL,
           parameters.to.save= jags.params,
           model.file = 'model_norm_norm_trend_Four_singleU_independentQs.txt',
           n.chains = MCMC.params$n.chains,
           n.burnin = MCMC.params$n.burnin,
           n.thin = MCMC.params$n.thin,
           n.iter = MCMC.params$n.samples,
           DIC = T, parallel=T)

#pull together results
# extract ys - include estimated missing data
ys.stats.JM <- data.frame(low = as.vector(t(jm$q2.5$y[,,1])),
                          median = as.vector(t(jm$q50$y[,,1])),
                          high = as.vector(t(jm$q97.5$y[,,1])))
ys.stats.JM$time <- data.jags.JM$data.1$Frac.Year
ys.stats.JM$obsY <- data.jags.JM$data.1$Nests
ys.stats.JM$month <- data.jags.JM$data.1$Month
ys.stats.JM$year <- data.jags.JM$data.1$Year
ys.stats.JM$Season <- data.jags.JM$data.1$Season
ys.stats.JM$location <- "Jamursba-Medi"

ys.stats.W <- data.frame(low = as.vector(t(jm$q2.5$y[,,2])),
                         median = as.vector(t(jm$q50$y[,,2])),
                         high = as.vector(t(jm$q97.5$y[,,2])))
ys.stats.W$time <- data.jags.JM$data.1$Frac.Year

ys.stats.W$obsY <- c(rep(NA, 
                         (12*(nrow(data.jags.JM$jags.data2$y) - nrow(data.jags.W$jags.data2$y)))),
                     data.jags.W$data.1$Nests)
ys.stats.W$month <- data.jags.JM$data.1$Month
ys.stats.W$year <- data.jags.JM$data.1$Year
ys.stats.W$Season <- data.jags.JM$data.1$Season
ys.stats.W$location <- "Wermon"

ys.stats <- rbind(ys.stats.JM, ys.stats.W)

# extract Xs - the state model

Xs.stats.JM <- data.frame(low = as.vector(t(jm$q2.5$X[,,1])),
                          median = as.vector(t(jm$q50$X[,,1])),
                          high = as.vector(t(jm$q97.5$X[,,1])))
Xs.stats.JM$time <- data.jags.JM$data.1$Frac.Year
Xs.stats.JM$obsY <- data.jags.JM$data.1$Nests
Xs.stats.JM$month <- data.jags.JM$data.1$Month
Xs.stats.JM$year <- data.jags.JM$data.1$Year
Xs.stats.JM$Season <- data.jags.JM$data.1$Season
Xs.stats.JM$location <- "Jamursba-Medi"

Xs.stats.W <- data.frame(low = as.vector(t(jm$q2.5$X[,,2])),
                         median = as.vector(t(jm$q50$X[,,2])),
                         high = as.vector(t(jm$q97.5$X[,,2])))
Xs.stats.W$location <- "Wermon"

Xs.stats.W$time <- data.jags.JM$data.1$Frac.Year
Xs.stats.W$obsY <- c(rep(NA, 
                         (12*(nrow(data.jags.JM$jags.data2$y) - nrow(data.jags.W$jags.data2$y)))),
                     data.jags.W$data.1$Nests)
Xs.stats.W$month <- data.jags.JM$data.1$Month
Xs.stats.W$year <- data.jags.JM$data.1$Year
Xs.stats.W$Season <- data.jags.JM$data.1$Season

Xs.stats <- rbind(Xs.stats.JM, Xs.stats.W)

Ns.stats.JM <- data.frame(time = year.begin.JM:year.end,
                          low = as.vector(t(jm$q2.5$N[1,])),
                          median = as.vector(t(jm$q50$N[1,])),
                          high = as.vector(t(jm$q97.5$N[1,])))
Ns.stats.JM$location <- "Jamursba-Medi"

Ns.stats.W <- data.frame(time = year.begin.JM:year.end,
                         low = as.vector(t(jm$q2.5$N[2,])),
                         median = as.vector(t(jm$q50$N[2,])),
                         high = as.vector(t(jm$q97.5$N[2,])))
Ns.stats.W$location <- "Wermon"

Ns.stats <- rbind(Ns.stats.JM, Ns.stats.W)

#Save results if needed

results.all <- list(jm = jm,
                    Xs.stats = Xs.stats,
                    ys.stats = ys.stats,
                    Ns.stats = Ns.stats)
if (save.data)
  saveRDS(results.all,
          file = paste0(filename.root, '.rds'))


#Look at some posteriors

# pop growth rates - over the entire time

bayesplot::mcmc_dens(jm$samples, c("U"))

# process SD for two beaches:

bayesplot::mcmc_dens(jm$samples, c("sigma.Q[1]", "sigma.Q[2]"))

# cos and sin for the discrete Foureir series 
bayesplot::mcmc_dens(jm$samples, c("p.beta.cos[1]", "p.beta.sin[1]",
                                   "p.beta.cos[2]", "p.beta.sin[2]"))

bayesplot::mcmc_dens(jm$samples, "sigma.N")

#Posteror on log(N) for JM
bayesplot::mcmc_dens(jm$samples, c("N[1,1]", "N[1,2]",
                                   "N[1,3]", "N[1,4]",
                                   "N[1,5]", "N[1,6]",
                                   "N[1,7]", "N[1,8]",
                                   "N[1,9]", "N[1,10]",
                                   "N[1,11]", "N[1,12]",
                                   "N[1,13]", "N[1,14]",
                                   "N[1,15]", "N[1,16]"))


#Posteror on log(N) for W

bayesplot::mcmc_dens(jm$samples, c("N[2,1]", "N[2,2]",
                                   "N[2,3]", "N[2,4]",
                                   "N[2,5]", "N[2,6]",
                                   "N[2,7]", "N[2,8]",
                                   "N[2,9]", "N[2,10]",
                                   "N[2,11]", "N[2,12]",
                                   "N[2,13]", "N[2,14]",
                                   "N[2,15]", "N[2,16]"))

p.1a <- ggplot() +
  geom_ribbon(data = Xs.stats,
              aes(x = time, 
                  ymin = low, 
                  ymax = high),
              fill = fill.color,
              alpha = fill.alpha) + 
  geom_point(data = Xs.stats,
             aes(x = time, 
                 y = median),
             color = data.color,
             alpha = 0.5) +
  geom_line(data = Xs.stats,
            aes(x = time, 
                y = median),
            color = line.color,
            alpha = 0.5) +
  geom_point(data = ys.stats,
             aes(x = time, 
                 y = log(obsY)),
             color = obsd.color,
             alpha = 0.5) + 
  geom_ribbon(data = Ns.stats,
              aes(x = time, 
                  ymin = low,
                  ymax = high),
              color = fill.color.N1,
              alpha = fill.alpha) + 
  geom_line(data = Ns.stats,
            aes(x = time, y = median),
            color = line.color.N,
            alpha = 0.5,
            size = 1.5) + 
  scale_x_continuous(breaks = seq(year.begin.JM, year.end, 5),
                     limits = c(year.begin.JM, year.end)) +
  scale_y_continuous(limits = c(0, log(maxN))) + 
  facet_grid(rows = vars(location)) + 
  labs(x = '', y = 'log(# nests)')  +
  theme(axis.text = element_text(size = 12),
        text = element_text(size = 12))

p.1a


p.1b <- ggplot() +
  geom_ribbon(data = Xs.stats,
              aes(x = time, 
                  ymin = exp(low), 
                  ymax = exp(high)),
              fill = fill.color,
              alpha = fill.alpha) + 
  geom_point(data = Xs.stats,
             aes(x = time, 
                 y = exp(median)),
             color = data.color,
             alpha = 0.5) +
  geom_line(data = Xs.stats,
            aes(x = time, 
                y = exp(median)),
            color = line.color,
            alpha = 0.5) +
  geom_point(data = ys.stats,
             aes(x = time, 
                 y = obsY),
             color = obsd.color,
             alpha = 0.5) + 
  geom_ribbon(data = Ns.stats,
              aes(x = time+0.5, 
                  ymin = exp(low),
                  ymax = exp(high)),
              color = fill.color.N1,
              alpha = fill.alpha) + 
  geom_line(data = Ns.stats,
            aes(x = time+0.5, 
                y = exp(median)),
            color = line.color.N,
            alpha = 0.5,
            size = 1.5) + 
  geom_point(data = Ns.stats,
             aes(x = time+0.5, 
                 y = exp(median)),
             color = "black",
             alpha = 0.5,
             size = 1.5) + 
  scale_x_continuous(breaks = seq(year.begin.JM, year.end, 5),
                     limits = c(year.begin.JM, year.end)) +
  scale_y_continuous(limits = c(0, 5000)) + 
  facet_grid(rows = vars(location)) + 
  labs(x = '', y = '# nests')  +
  theme(axis.text = element_text(size = 12),
        text = element_text(size = 12))

p.1b

#save plots if requested

if (save.fig){
  # ggsave(filename = paste0("figures/", filename.root, ".png"),
  #        plot = p.1,
  #        dpi = 600,
  #        device = "png")
  
  ggsave(filename = paste0(filename.root, ".png"),
         plot = p.1a,
         dpi = 600,
         device = "png")
  
  # ggsave(filename = paste0("figures/", filename.root,  "_pareto.png"),
  #      plot = p.2,
  #      dpi = 600,
  #      device = "png")
  
}

```

