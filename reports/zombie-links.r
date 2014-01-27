library(sqldf)
library(ggplot2)
library(reshape2)
library(scales)
library(knitr)

get.datasets <- function() {
  sql <- '
  -- CKAN
  SELECT 
    software, catalog, identifier, status_code
  FROM links
  WHERE software = \'ckan\'

  UNION ALL

  -- Socrata
  SELECT 
    links.software, links.catalog, links.identifier, status_code
  FROM socrata_deduplicated
  JOIN links
  WHERE socrata_deduplicated.catalog = links.catalog
    AND socrata_deduplicated.tableId = links.identifier
  GROUP BY links.identifier
  ;'

  datasets <- with(new.env(), sqldf(sql, dbname = '/tmp/open-data.sqlite'))

  datasets$software <- factor(datasets$software)
  datasets$catalog <- factor(datasets$catalog)
  datasets$status_code <- factor(datasets$status_code)
  levels(datasets$status_code)[grep('-42', levels(datasets$status_code))] <- 'Timeout'
  datasets$status_code <- factor(datasets$status_code,
    levels = c(sort(levels(datasets$status_code)), NA), exclude = c())
  levels(datasets$status_code)[is.na(levels(datasets$status_code))] <- 'Not link'

  datasets
}

if (!all(list('datasets', 'catalogs') %in% ls())) {
  datasets <- get.datasets()
  catalogs <- sqldf('
SELECT
  catalog,
  avg(status_code == \'Timeout\') \'timeouts\',
  sum(status_code != \'Not link\') \'links\',
  count(*) \'datasets\'
FROM datasets GROUP BY catalog')
}

p.codes <- ggplot(datasets) + aes(x = status_code) + geom_bar() +
  xlab('HTTP status code') +
  scale_y_continuous('Number of datasets', labels = comma) +
  ggtitle('Which status codes were returned when I checked link liveliness?')

p.data.openva.com <- ggplot(subset(datasets, catalog == 'data.openva.com')) +
  aes(x = status_code) + geom_bar() +
  xlab('HTTP status code') +
  scale_y_continuous('Number of datasets', labels = comma) +
  ggtitle('Which status codes were returned when I checked link liveliness on data.openva.com?')

p.dati.trentino.it <- ggplot(subset(datasets, catalog == 'dati.trentino.it')) +
  aes(x = status_code) + geom_bar() +
  xlab('HTTP status code') +
  scale_y_continuous('Number of datasets', labels = comma) +
  ggtitle('Which status codes were returned when I checked link liveliness on dati.trentino.it?')

p.timeouts <- ggplot(catalogs) +
  aes(x = catalog, y = timeouts, width = links / sum(links)) +
  geom_bar(stat = 'identity', position = 'identity') +
  coord_flip()

p.catalogs <- ggplot(catalogs) +
  aes(x = links, y = timeouts) +
  geom_point()

# knit('zombie-links.Rmd')
