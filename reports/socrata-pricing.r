library(sqldf)
library(ggplot2)
library(reshape2)

q <- function(sql) {
  sqldf(sql, dbname = '/tmp/open-data.sqlite')
}

catalogs <- q('SELECT * FROM pricing')
rownames(catalogs) <- catalogs$catalog
catalogs[-1] <- as.data.frame(lapply(catalogs[-1],as.integer))
# catalogs$catalog <- NULL
catalogs[is.na(catalogs)] <- 0

catalogs$has.forms <- factor(catalogs$n_forms > 0, levels = c(TRUE,FALSE))
catalogs$has.apis <- factor(catalogs$n_apis > 0, levels = c(TRUE,FALSE))
catalogs$has.311 <- factor(catalogs$n_311 > 0, levels = c(TRUE,FALSE))
levels(catalogs$has.forms) <-
  levels(catalogs$has.apis) <-
  levels(catalogs$has.311) <-
  c('Yes','No')

# Guess the plans
catalogs$data.portal.plan <- factor('SOC-OD-B',
  levels = c(paste0('SOC-OD-', c('B','Ext','Ent')), 'Other'))

catalogs$data.portal.plan[catalogs$n_datasets > 150] <- 'SOC-OD-Ext' 
catalogs$data.portal.plan[catalogs$n_datasets > 500] <- 'SOC-OD-Ent'
catalogs$data.portal.plan[catalogs$n_datasets >1500] <- 'Other'

catalogs$data.portal.plan[catalogs$n_apis > 10] <- 'SOC-OD-Ext' 
catalogs$data.portal.plan[catalogs$n_apis > 25] <- 'SOC-OD-Ent'
catalogs$data.portal.plan[catalogs$n_apis > 50] <- 'Other'

catalogs$data.collect.plan <- factor('None',
  levels = c('None', paste0('SOC-DC-', c('B','Ext','Ent')), 'Other'))

catalogs$data.collect.plan[catalogs$n_forms >  0] <- 'SOC-DC-B' 
catalogs$data.collect.plan[catalogs$n_forms > 50] <- 'SOC-DC-Ext' 
catalogs$data.collect.plan[catalogs$n_forms >100] <- 'SOC-DC-Ent'
catalogs$data.collect.plan[catalogs$n_forms >200] <- 'Other'

# Plots

molten <- melt(catalogs, variable.name = 'has', value.name = 'yes',
  measure.vars = grep('has.', names(catalogs), value = TRUE))

p1 <- ggplot(catalogs) + aes(x = n_datasets, y = n_apis, color = n_forms > 0) +
  scale_x_log10('Number of datasets') + scale_y_log10('Number of APIs') +
  geom_point(size = 5)

p2 <- ggplot(molten) + aes(x = n_datasets, fill = yes) +
  facet_wrap(~ has) +
  geom_bar()

p3 <- ggplot(catalogs) + aes(x = n_forms, y = n_datasets, label = catalog) +
  facet_grid(has.apis ~ has.311) +
  scale_y_log10('Number of datasets') + scale_x_log10('Number of formss') +

  # Socrata Open Data Portal plans
  geom_hline(yintercept = c(150, 500, 1500), color = 'grey') + 

  # Socrata Data Collect plans
  geom_vline(xintercept = c(50, 100, 200), color = 'grey') + 

  geom_text()

p4 <- ggplot(catalogs) + aes(x = n_geo, y = n_datasets, label = catalog, color = has.apis) +
  scale_y_log10('Number of datasets') + scale_x_log10('Number of geospatial datasets') +

  # Dataset count thresholds for Socrata Open Data Portal plans
  geom_hline(yintercept = c(150, 500, 1500), color = 'grey') + 

  geom_text()

p5.base <- ggplot(catalogs) + aes(x = n_datasets, y = n_apis, label = catalog) +
# scale_x_log10('Number of datasets') + scale_y_log10('Number of APIs') +

  # Dataset count thresholds for Socrata Open Data Portal plans
  geom_vline(xintercept = c(150, 500, 1500), color = 'grey') + 

  # API count thresholds for Socrata Open Data Portal plans
  geom_hline(yintercept = c(10, 25, 50), color = 'grey')

p5.text <- p5.base + geom_text()
p5.point <- p5.base + geom_point()


t1 <- table(catalogs$has.forms, catalogs$has.apis, catalogs$has.311)

cat('To do: Guess the plans.\n')
