---
draft : false
---

## Calculating Historical Intercapital Distances

*Last updated 10 January 2018*

Military power degrades with distance. Fighting a war on another continent is, for most militaries, more difficult than fighting at home. Studies of conflict frequently employ capital-to-capital distance (or some transformation of this metric) as one proxy for this loss of strength from power projection (see, for example, (Gartzke and Braithwaite (2011)). Combined with [data on territorial contiguity](http://www.correlatesofwar.org/data-sets/direct-contiguity), these metrics can provide us with a picture of the geographic constraints facing countries contemplating war with one another.

Historical intercapital distance data proved difficult to find however. Most researchers appear to rely on [EuGene](http://eugenesoftware.org/welcome.asp) to generate this data. I wasn't able to track down any documentation on exactly how EuGene does this, however.[^1] Gleditsch and Ward (2001) generated a *minimum* interstate distance dataset, but their data only covers the post-1875 period. For researchers using [Correlates of War](http://www.correlatesofwar.org/) data, distance data would ideally cover 1816 to the present.

[^1]: Tips on where to find this documentation are more than welcome.

It turns out that it's not too difficult to build intercapital distance data from scratch, however. All that is required is data on the *names* of capital cities for each state system member for every year between 1816 and the present. Paul Hensel's [ICOW Historical State Names dataset](http://www.paulhensel.org/icownames.html) provides this information. We can then use Google's [Geocoding API](https://developers.google.com/maps/documentation/geocoding/start) through the `ggmap` R package to get the coordinates of each historical capital, which can then be used to generate intercapital distance matrices.

Here, I show how to conduct this exercise in R. A clean version of Hensel's historical capital dataset is available [here](https://github.com/brendancooley/intercapital-distances/blob/master/capitals.csv). I've included all of the data and software necessary to generate this data on [Github](https://github.com/brendancooley/intercapital-distances). Feel free to send along questions, comments, or suggestions for improvement to [bcooley@princeton.edu](mailto:bcooley@princeton.edu).

#### Capital City Coordinates

Start by loading up the packages we'll need for analysis:


```r
libs <- c('readr', 'dplyr', 'tidyr', 'ggmap', 'geosphere', 'leaflet', 'knitr', 'bibtex', 'knitcitations')
sapply(libs, require, character.only = TRUE)
```

I started by cleaning up Hensel's data a bit in excel. Each capital city is listed as its own observation, along with the country, its COW code, and the first and last year the city served as a capital. Because the Hensel data is coded annually, I take the country's capital at the start of any given year to be its capital for that entire year. For countries that no longer exist (e.g. Mecklenburg-Schwerin) I provide a contemporary alternative country name (aName) to help Google locate the city's coordinates. The assumption underlying this procedure is that the cities that served as capitals historically have not moved from their historical location (if I'm missing any instances where this occured please let me know). We can take a look at the data below:

```r
# load data
dists <- read_csv('capitals.csv')

# Hensel's data run from 1800-2016, set bounds
dists$startDate <- ifelse(is.na(dists$startDate), 1800, dists$startDate)
dists$endDate <- ifelse(is.na(dists$endDate), 2016, dists$endDate)

head(dists)
```

```
## # A tibble: 6 x 6
##   ccode Name                     aName startDate endDate Capital
##   <int> <chr>                    <chr>     <dbl>   <dbl> <chr>
## 1     2 United States of America <NA>       1800    2016 Washington D.C.
## 2    20 Canada                   <NA>       1800    1841 Ottawa
## 3    20 Canada                   <NA>       1841    1843 Kingston
## 4    20 Canada                   <NA>       1843    1849 Montreal
## 5    20 Canada                   <NA>       1849    1859 Toronto
## 6    20 Canada                   <NA>       1859    1865 Quebec City
```

Now we need to get the cities' coordinates. I simply feed the City, Country tuples to `ggmap`'s `geocode` function, which returns lat, lng coordinates if it can find a match in Google's database. If the country has a contemporary name, I use this name for the search in lieu of its old name. I save these coordinates to the `dists` data frame when they are found. The `geocode` API imposes some query limits, so it sometimes throws an `OVER_QUERY_LIMIT` error. If cities remain uncoded, I simply run the loop again, skipping over those that already have coordinates. We can check that the coding worked with the `dists %>% filter(is.na(lat))`, which should return an empty data frame if all cities have been geocoded.


```r
# initialize coordinates
dists$lat <- NA
dists$lng <- NA

# run until all cities have been coded
while(nrow(dists %>% filter(is.na(lat))) > 0) {
  # for each city
  for (i in 1:nrow(dists)) {
    # skip if it's already been coded
    if (is.na(dists[i,]$lat)) {
      if (is.na(dists[i,]$aName)) {
        # query City, Country for each capital
        query <- paste0(dists[i, ]$Capital, ", ", dists[i, ]$Name)
        latlng <- geocode(query)
        dists[i, ]$lat <- latlng$lat
        dists[i, ]$lng <- latlng$lon
      }
      else {
        # use alternative country name
        query <- paste0(dists[i, ]$Capital, ", ", dists[i, ]$aName)
        latlng <- geocode(query)
        dists[i, ]$lat <- latlng$lat
        dists[i, ]$lng <- latlng$lon
      }
    }
  }
}
```

We can check to make sure the cities were coded correctly by plotting them on a map. Clicking on the city will show a popup with its name. I poked around this map a bit and everything seemed to land in the right spot.


```r
leaflet(data=dists) %>% addProviderTiles(providers$CartoDB.Positron, options=providerTileOptions(minZoom = 1)) %>%
  addCircleMarkers(~lng, ~lat, popup=~Capital, radius=1) %>%
  setMaxBounds(-180, -90, 180, 90)
```

<iframe src="https://cdn.rawgit.com/brendancooley/intercapital-distances/099ee110/dists-map.html" width="700" height="500"></iframe>

I then export the geocoded capitals as a csv. You can find these data [here](https://github.com/brendancooley/intercapital-distances/blob/master/dists.csv).


```r
write_csv(dists, 'dists.csv')
```

#### Intercapital Distances

Remember that the point of all this was to generate intercapital distance data for all countries in the COW data. To do this, we want to convert our geocoded capital city data into a dyadic time series that gives the distance between any two countries' capitals for a given year. If there are $N$ countries in the system in a given year $t$, we want to be able to generate an $N \times N$ matrix for that year where each entry is the distance between countries $i$ and $j$.

I start by loading up COW's state system membership data, so we know which countries were members of the system for each year. The field "styear" denotes the year the country entered the system, and the field "endyear" gives the year it exited. I then append this data to the distance data. The output is shown below.

```r
dists <- read_csv('dists.csv')

# get state system membership (COW)
sysMemUrl <- "http://www.correlatesofwar.org/data-sets/state-system-membership/states2016/at_download/file"

sysMem <- read_csv(sysMemUrl) %>% select(ccode, styear, endyear)
dists <- left_join(dists, sysMem, by="ccode")

head(dists)
```

```
## # A tibble: 6 x 10
##   ccode Name         aName startD… endDa… Capital    lat   lng stye… endy…
##   <int> <chr>        <chr>   <int>  <int> <chr>    <dbl> <dbl> <int> <int>
## 1     2 United Stat… <NA>     1800   2016 Washing…  38.9 -77.0  1816  2016
## 2    20 Canada       <NA>     1800   1841 Ottawa    45.4 -75.7  1920  2016
## 3    20 Canada       <NA>     1841   1843 Kingston  44.2 -76.5  1920  2016
## 4    20 Canada       <NA>     1843   1849 Montreal  45.5 -73.6  1920  2016
## 5    20 Canada       <NA>     1849   1859 Toronto   43.7 -79.4  1920  2016
## 6    20 Canada       <NA>     1859   1865 Quebec …  46.8 -71.2  1920  2016
```

From this dataframe, I can build the $N \times N$ intercapital distance matrix for any year. I wrap this in a function `coord2DistM`, which takes the desired year and the dists dataframe as arguments. It filters the distance data to include only states that were active in that year. It then feeds the latitude and longitude coordinates to the `distm` function from the `geosphere` package, which retuns the desired distance matrix. I convert all distances to kilometers.

The function `distM2dydist` takes this distance matrix and a pair of COW country codes and returns the dyadic distance. Below, I show how to use these functions to build the intercapital distance matrix for the year 1816 and get the distance between Britain and Saxony.


```r
# Note: assigns capital to city that was capital at beginning of year

coord2DistM <- function(dists, year) {
  # filter by system membership, then relevant capital
  distsY <- dists %>% filter(styear <= year, endyear >= year) %>% filter(startDate < year & endDate >= year)
  # check that one capital returned per country
  if (length(unique(distsY$Capital)) != length(unique(distsY$Name))) {
    print('error: nCountries != nCapitals, check underlying coordinate data')
  }
  else {
    # get distance matrix for selected year
    latlng <- distsY %>% select('lng', 'lat') %>% as.matrix()
    distsYmatrix <- distm(latlng, latlng, fun=distVincentySphere)
    distsYmatrix <- distsYmatrix / 1000  # convert to km
    rownames(distsYmatrix) <- colnames(distsYmatrix) <- distsY$ccode
    return(distsYmatrix)
  }
}

# get distance between i and j
distM2dydist <- function(distM, ccode1, ccode2) {
  return(distM[ccode1, ccode2])
}

# application
year <- 1816
Britain <- "200"
Saxony <- "269"

distM1816 <- coord2DistM(dists, year)
distM2dydist(distM1816, Britain, Saxony)
```

```
## [1] 965.3628
```

These functions can be used in tandem to grab intercapital distances for arbitrary year, dyad pairings.

#### Merge with COW War Data

Conflict researchers often want this data to analyze wars. Now I show how to merge intercapital distance data with COW's inter-state-war data. I clean up the COW war data a bit, which you can see below post-cleaning. In the most basic leve, the data give information about the belligerents in every war and how long each war lasted.


```r
# append to COW wars data
warUrl <- "http://www.correlatesofwar.org/data-sets/COW-war/inter-state-war-data/at_download/file"
cowWars <- read_csv(warUrl)

# for simplicity, ignore armistices
cowWars$StartYear <- cowWars$StartYear1
cowWars$EndYear <- ifelse(cowWars$EndYear2 == -8, cowWars$EndYear1, cowWars$EndYear2)
cowWars <- cowWars %>% select(WarName, ccode, StateName, Side, StartYear, EndYear)

head(cowWars)
```

```
## # A tibble: 6 x 6
##   WarName             ccode StateName                 Side StartYear EndY…
##   <chr>               <int> <chr>                    <int>     <int> <int>
## 1 Franco-Spanish War    230 Spain                        2      1823  1823
## 2 Franco-Spanish War    220 France                       1      1823  1823
## 3 First Russo-Turkish   640 Ottoman Empire               2      1828  1829
## 4 First Russo-Turkish   365 Russia                       1      1828  1829
## 5 Mexican-American       70 Mexico                       2      1846  1847
## 6 Mexican-American        2 United States of America     1      1846  1847
```

We want to know the intercapital distance between each pair of belligerents between 1816 and the present. We could use the `coord2DistM` and `distM2dydist` but this would require calculating the intercapital distance matrix for every year in which there was a war. A simpler solution is to build a dataframe of capital-years, along with their coordinates, merge this with the war data, and calculate the distance between belligerents, given their capitals' coordinates.

I used the procedure in this [stackoverflow post](https://stackoverflow.com/questions/28553762/expand-year-range-in-r) to create the capital-year dataframe. Once merged, I use `geosphere`'s `distVicentySphere` function to calculate the distances. The resulting data is shown below the code.


```r
# convert capital data to yearly observations
# https://stackoverflow.com/questions/28553762/expand-year-range-in-r
distsYear <- dists
distsYear$year <- mapply(seq, distsYear$startDate, distsYear$endDate, SIMPLIFY=FALSE)
distsYear <- distsYear %>%
  unnest(year) %>%
  select(ccode, year, lat, lng)

# get capital in start year
cowWars$year <- cowWars$StartYear

# append coords for each side
cowWars1 <- cowWars %>% filter(Side == 1) %>% left_join(distsYear, by=c("ccode", "year")) %>% rename(State1 = StateName, ccode1 = ccode, lat1 = lat, lng1 = lng) %>% select(-Side)
cowWars2 <- cowWars %>% filter(Side == 2) %>% left_join(distsYear, by=c("ccode", "year")) %>% rename(State2 = StateName, ccode2 = ccode, lat2 = lat, lng2 = lng) %>% select(WarName, State2, ccode2, lat2, lng2)

cowWarsDyadic <- left_join(cowWars1, cowWars2, by="WarName") %>% select(WarName, ccode1, State1, ccode2, State2, year, lng1, lat1, lng2, lat2)

# calculate distance
latlng1 <- cowWarsDyadic %>% select(lng1, lat1)
latlng2 <- cowWarsDyadic %>% select(lng2, lat2)
cowWarsDyadic$distance <- distVincentySphere(latlng1, latlng2) / 1000  # convert to km

# export data
write_csv(cowWarsDyadic, 'cowWarsDist.csv')

cowWarsDyadic %>% select(WarName, ccode1, State1, ccode2, State2, distance)
```

```
## # A tibble: 813 x 6
##    WarName                  ccode1 State1          ccode2 State2    dista…
##    <chr>                     <int> <chr>            <int> <chr>      <dbl>
##  1 Franco-Spanish War          220 France             230 Spain       1054
##  2 Franco-Spanish War          220 France             230 Spain       1054
##  3 First Russo-Turkish         365 Russia             640 Ottoman …   2233
##  4 Mexican-American              2 United States …     70 Mexico      3035
##  5 Austro-Sardinian            300 Austria            337 Tuscany      632
##  6 Austro-Sardinian            300 Austria            325 Italy        765
##  7 Austro-Sardinian            300 Austria            332 Modena       575
##  8 First Schleswig-Holstein    255 Prussia            390 Denmark      356
##  9 First Schleswig-Holstein    255 Prussia            390 Denmark      356
## 10 First Schleswig-Holstein    255 Prussia            390 Denmark      356
## # ... with 803 more rows
```

The resulting data can be found [here](https://github.com/brendancooley/intercapital-distances/blob/master/cowWarsDist.csv).

#### R Packages

Wickham H, Hester J and Francois R (2017). _readr: Read Rectangular Text Data_. R package
version 1.1.1, <URL: https://CRAN.R-project.org/package=readr>.

Wickham H, Francois R, Henry L and Müller K (2017). _dplyr: A Grammar of Data Manipulation_. R
package version 0.7.4, <URL: https://CRAN.R-project.org/package=dplyr>.

Wickham H and Henry L (2017). _tidyr: Easily Tidy Data with 'spread()' and 'gather()'
Functions_. R package version 0.7.2, <URL: https://CRAN.R-project.org/package=tidyr>.

Kahle D and Wickham H (2013). “ggmap: Spatial Visualization with ggplot2.” _The R Journal_,
*5*(1), pp. 144-161. <URL: http://journal.r-project.org/archive/2013-1/kahle-wickham.pdf>.

Hijmans RJ (2016). _geosphere: Spherical Trigonometry_. R package version 1.5-5, <URL:
https://CRAN.R-project.org/package=geosphere>.

Cheng J, Karambelkar B and Xie Y (2017). _leaflet: Create Interactive Web Maps with the
JavaScript 'Leaflet' Library_. R package version 1.1.0, <URL:
https://CRAN.R-project.org/package=leaflet>.

Xie Y (2017). _knitr: A General-Purpose Package for Dynamic Report Generation in R_. R package
version 1.18, <URL: https://yihui.name/knitr/>.

Xie Y (2015). _Dynamic Documents with R and knitr_, 2nd edition. Chapman and Hall/CRC, Boca
Raton, Florida. ISBN 978-1498716963, <URL: https://yihui.name/knitr/>.

Xie Y (2014). “knitr: A Comprehensive Tool for Reproducible Research in R.” In Stodden V,
Leisch F and Peng RD (eds.), _Implementing Reproducible Computational Research_. Chapman and
Hall/CRC. ISBN 978-1466561595, <URL: http://www.crcpress.com/product/isbn/9781466561595>.

Francois R (2017). _bibtex: Bibtex Parser_. R package version 0.4.2, <URL:
https://CRAN.R-project.org/package=bibtex>.

Boettiger C (2017). _knitcitations: Citations for 'Knitr' Markdown Files_. R package version
1.0.8, <URL: https://CRAN.R-project.org/package=knitcitations>.

#### References

Gartzke, Erik, and Alex Braithwaite. 2011. “Power, Parity and Proximity.”

Gleditsch, Kristian S, and Michael D Ward. 2001. “Measuring space: A minimum-distance database and applications to international studies.” Journal of Peace Research 38 (6).
