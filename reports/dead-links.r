library(sqldf)
library(ggplot2)
library(reshape2)
library(scales)
library(knitr)

get.datasets <- function() {
  sql <- '
  -- CKAN
  SELECT 
    software, catalog, identifier,
    is_link, status_code,
    coalesce(status_code < 200, NOT is_link) \'alive\'
  FROM links
  WHERE software = \'ckan\'

  UNION ALL

  -- Socrata
  SELECT 
    links.software, links.catalog, links.identifier,
    is_link, status_code,
    coalesce(status_code < 400, NOT is_link) \'alive\'
  FROM socrata_deduplicated
  JOIN links
  WHERE socrata_deduplicated.catalog = links.catalog
    AND socrata_deduplicated.tableId = links.identifier
  GROUP BY links.identifier
  ;'

  datasets <- with(new.env(), sqldf(sql, dbname = '/tmp/open-data.sqlite'))

  datasets$software <- factor(datasets$software)
  datasets$catalog <- factor(datasets$catalog)
  datasets$alive.factor <- factor(datasets$alive, levels = 1:0)
  levels(datasets$alive.factor) <- c('Alive','Dead')
  datasets$status_code <- factor(datasets$status_code)
  datasets$status_code[datasets$status_code == '-42'] <- NA

  datasets
}

get.catalogs <- function(datasets) {
  catalogs <- sqldf('
  SELECT
    a.software, a.catalog,
    a.prop_links,
    a.prop_alive,
    a.n_datasets,
    b.prop_live_links
  FROM (
    SELECT
      software, catalog,
      avg(is_link) prop_links,
      avg(alive) prop_alive,
      count(*) n_datasets
    FROM datasets
    GROUP BY catalog
  ) a
  LEFT JOIN (
    SELECT
      software, catalog, avg(alive) prop_live_links
    FROM datasets
    WHERE is_link
    GROUP BY catalog
  ) b
  ON a.catalog = b.catalog
  ')

  # Order by liveliness.
  catalogs$catalog <- factor(catalogs$catalog,
    levels = catalogs$catalog[order(catalogs$prop_alive)])

  catalogs$has_links <- factor(catalogs$prop_links > 0, levels = c(TRUE, FALSE))
  levels(catalogs$has_links) <- c('Yes','No')

  rownames(catalogs) <- catalogs$catalog

  catalogs
}

get.link.groupings <- function(catalogs) {
  catalogs$p <- catalogs$prop_live_links
  catalogs$p[is.na(catalogs$p)] <- 0

  catalogs$not.links <- 1 - catalogs$prop_links
  catalogs$live.links <- catalogs$prop_links * catalogs$p
  catalogs$dead.links <- catalogs$prop_links * (1 - catalogs$p)
  
  link.groupings <- melt(catalogs,
    id.vars = c('software','catalog'),
    measure.vars = paste(c('not', 'live', 'dead'), 'links', sep = '.'),
    variable.name = 'link.type', value.name = c('proportion'))

  link.groupings
}

if (!all(list('datasets','catalogs','link.groupings') %in% ls())) {
  datasets <- get.datasets()
  catalogs <- get.catalogs(datasets)
  link.groupings <- get.link.groupings(catalogs)
}

p.has_links.socrata <- qplot(data = subset(catalogs, software == 'socrata'),
  x = ' ',
  fill = has_links, position = 'fill', geom = 'bar') +
  scale_y_continuous('Proportion of data catalogs', labels = percent) +
  scale_fill_discrete('Has links?') +
  theme(legend.position = 'none') +
  coord_flip() +
  xlab('') +
  annotate('text', y = c(0.18, 0.69), x = 1,
    label = c('Catalogs with\nexternal links', 'Catalogs without\nexternal links')) +
  ggtitle('Socrata catalogs with externally stored datasets')

p.has_links <- qplot(data = catalogs, x = software, fill = has_links,
  position = 'fill', geom = 'bar') +
  xlab('Software') +
  scale_y_continuous('Proportion of data catalogs', labels = percent) +
  scale_fill_discrete('Has links?') +
  theme(legend.position = 'bottom') +
  coord_flip() +
  ggtitle('Proportion of data catalogs\nwith externally stored datasets')

p.software <- ggplot(catalogs) +
  aes(x = catalog, y = prop_alive, fill = software) +
  scale_y_continuous('Proportion of datasets with live links', labels = percent) +
  xlab('Data catalog') +
  theme(legend.position = 'bottom', axis.text.y = element_text(size = 10)) +
  ggtitle('Dataset liveliness by data catalog') +
  geom_bar(stat = 'identity') + coord_flip()

p.prop_links.socrata <- ggplot(subset(catalogs, software == 'socrata')) +
  aes(x = prop_links, y = prop_alive) +
  geom_point() +
  scale_x_continuous('Proportion of datasets that are externally stored', labels = percent) +
  scale_y_continuous('Proportion of datasets that are alive', labels = percent) +
  ggtitle('On Socrata, only externally stored data can be dead.\n(Duh)')

p.prop_links <- ggplot(catalogs) +
  aes(x = prop_links, y = prop_alive, color = software) +
  geom_point() +
  scale_x_continuous('Proportion of datasets that are externally stored', labels = percent) +
  scale_y_continuous('Proportion of datasets that are alive', labels = percent, limits = 0:1) +
  theme(legend.position = 'bottom') +
  scale_color_discrete('Software') +
  ggtitle('CKAN catalogs have more externally stored datasets\nand more dead datasets.')

p.software.all_types <- ggplot(link.groupings) +
  aes(x = catalog, y = proportion, fill = link.type) +
  geom_bar(stat = 'identity') + coord_flip() +
  xlab('') +
  scale_y_continuous('Proportion of datasets by catalog', labels = percent) +
  theme(legend.position = 'bottom', axis.text.y = element_text(size = 10)) +
  scale_fill_discrete('Type of dataset') +
  ggtitle('Non-links, live links and dead links across data catalogs')

p.software.only_links <- ggplot(catalogs) +
  aes(x = catalog, y = prop_live_links, fill = software) +
  geom_bar(stat = 'identity') + coord_flip() +
  xlab('') +
  scale_y_continuous('Proportion of datasets by catalog', labels = percent) +
  theme(legend.position = 'bottom', axis.text.y = element_text(size = 10)) +
  scale_fill_discrete('Software') +
  ggtitle('Of only the external links, what proportion of datasets are alive?')

knit('dead-links.Rmd')

# plot(prop_alive ~ log(n_datasets), data = catalogs, col = software) 
