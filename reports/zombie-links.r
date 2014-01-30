library(sqldf)
library(ggplot2)
library(reshape2)
library(scales)
library(knitr)
library(httr)

get.datasets <- function() {
  sql <- '
  -- CKAN
  SELECT 
    software, catalog, identifier, status_code, url
  FROM links
  WHERE software = \'ckan\'
  GROUP BY links.catalog, links.identifier

  UNION ALL

  -- Socrata
  SELECT 
    links.software, links.catalog, links.identifier, status_code, url
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

get.catalogs <- function(datasets) {
  catalogs <- sqldf('
SELECT
  software,
  catalog,
  sum(status_code == \'Timeout\') \'timeouts\',
  sum(status_code == \'Not link\') \'not_links\',
  sum(status_code != \'Not link\' AND status_code != \'Timeout\' AND status_code = 200) \'live_links\',
  sum(status_code != \'Not link\' AND status_code != \'Timeout\' AND status_code != 200 AND status_code NOT NULL) \'dead_links\',
  count(*) \'datasets\'
FROM datasets GROUP BY catalog')
  catalogs$prop.bad <- catalogs$live_links / (catalogs$datasets - catalogs$not_links)
  catalogs$catalog <- factor(catalogs$catalog,
    levels = catalogs$catalog[order(catalogs$prop.bad, decreasing = TRUE)])
  catalogs
}

get.link.groupings <- function(catalogs) {
  for (column in c('timeouts','not_links','live_links','dead_links')){
    catalogs[,column] <- catalogs[,column] / catalogs$datasets
  }

  link.groupings <- melt(catalogs,
    id.vars = c('software','catalog'),
    measure.vars = c('not_links','live_links','dead_links','timeouts'),
    variable.name = 'link.type', value.name = c('proportion'))

  link.groupings <- link.groupings[order(link.groupings$catalog),]
  link.groupings$catalog <- factor(link.groupings$catalog,
    levels = levels(catalogs$catalog)[order(catalogs$prop.bad)])

  link.groupings
}


get.duplicates <- function() {
  sql = '
SELECT
  software, catalog, identifier, error,
  (min(status_code) = max(status_code)) same_status_code,
  count(*) n, round(avg(is_link)) is_link
FROM links
GROUP BY catalog, identifier
'
  unique.links <- with(new.env(), sqldf(sql, dbname = '/tmp/open-data.sqlite'))
  unique.links
}

if (!all(list('datasets', 'catalogs', 'unique.links', 'link.groupings') %in% ls())) {
# datasets <- get.datasets()
  datasets[!is.na(datasets$url),'hostname'] <- sapply(datasets[!is.na(datasets$url),'url'], function(x){parse_url(x)$hostname})
  catalogs <- get.catalogs(datasets)
  unique.links <- get.duplicates()
  link.groupings <- get.link.groupings(catalogs)
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

p.bad <- ggplot(subset(catalogs, datasets > 0)) +
  aes(x = catalog, y = prop.bad, fill = software) +
  geom_bar(stat = 'identity') +
  xlab('Data catalog\n(Only data catalogs with externally stored datasets are included.)') +
  scale_y_continuous('Proportion of external datasets that timed out', labels = percent) +
  ggtitle('External link timeouts by data catalog') +
  theme(legend.position = 'bottom') +
  coord_flip()

p.catalogs <- ggplot(catalogs) +
  aes(x = links, y = timeouts, color = catalog == 'data.openva.com' | catalog == 'dati.trentino.it', label = catalog) +
  theme(legend.position = 'none') +
  scale_x_log10('Number of external links on the catalog', labels = comma, breaks = 10^(0:5)) +
  scale_y_log10('Number of timeouts when accessing external links', labels = comma, breaks = 10^(0:5)) +
  geom_text(size = 7, alpha = 0.5)

p.duplicates.ckan <- ggplot(subset(unique.links, software == 'ckan')) +
  aes(x = n) + facet_wrap(~ is_link, nrow = 2) + geom_histogram()

p.duplicates.socrata <- ggplot(subset(unique.links, software == 'socrata')) +
  aes(x = n) + facet_wrap(~ is_link, nrow = 2) + geom_histogram() +
  scale_y_sqrt()

unique.links.socrata <- subset(unique.links, software == 'socrata' & is_link)
table.duplicates.socrata <- table(subset(unique.links, software == 'socrata' & is_link)$n)
table.duplicates.socrata.by.catalog <- table(unique.links.socrata$catalog, unique.links.socrata$n)

p.link.types <- ggplot(link.groupings) +
  aes(x = catalog, y = proportion, fill = link.type) +
  geom_bar(stat = 'identity') + coord_flip() +
  xlab('') +
  scale_y_continuous('Proportion of datasets by catalog', labels = percent) +
  theme(legend.position = 'bottom', axis.text.y = element_text(size = 10)) +
  scale_fill_discrete('Type of dataset') +
  ggtitle('Non-links, live links and dead links across data catalogs')

p.link.types.specifics <- ggplot(subset(link.groupings, catalog == 'dati.trentino.it' | catalog == 'data.openva.com')) +
  aes(x = catalog, y = proportion, fill = link.type) +
  geom_bar(stat = 'identity') + coord_flip() +
  xlab('') +
  scale_y_continuous('Proportion of datasets by catalog', labels = percent) +
  theme(legend.position = 'bottom', axis.text.y = element_text(size = 10)) +
  scale_fill_discrete('Type of dataset') +
  ggtitle('Non-links, live links and dead links across data catalogs')


# knit('zombie-links.Rmd')
