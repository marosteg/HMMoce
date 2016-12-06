#' OHC Parallel
#' Calculate Ocean Heat Content (OHC) probability surface in parallel
#'
#' @param pdt input PAT data see \code{\link{extract.pdt}}
#' @param ptt name of tag i.e. 123645
#' @param isotherm if specifying a particular isotherm, otherwise leave blank. default value is 
#' @param ohc.dir directory of downloaded hycom (or other)data
#' @param dateVec vector of complete dates for data range. This should be in 'Date' format
#' @param bathy should the land be flagged out? defaults to TRUE
#' @param ncores specify number of cores, or leave blank and use whatever you have!
#'
#' @return a raster brick of OHC likelihood
#' @seealso \code{\link{calc.ohc}}
#' @export
#'
#' @examples
#' # load workspace
#' load('~/DATA/blue259_forParallel.RData')

#' # define ohc.dir
#' ohc.dir = '~/hycom/'
#' # run in parallel
#' res = calc.ohc.par(pdt, ptt, isotherm = '', ohc.dir = ohc.dir, dateVec = dateVec, bathy = T)


calc.ohc.par <- function(pdt, ptt, isotherm = '', ohc.dir, dateVec, bathy = TRUE, ncores = detectCores()){
  
  max_ohc_date = max(as.Date(substr(dir(ohc.dir), 8, 17)))
  pdt_idx = as.Date(pdt$Date)<=max_ohc_date
  pdt = pdt[pdt_idx, ]
  
  dvidx = dateVec <= max_ohc_date
  
  dateVec = dateVec[dvidx]
  
  require(lubridate)
  
  options(warn=1)
  
  start.t <- Sys.time()
  
  # constants for OHC calc
  cp <- 3.993 # kJ/kg*C <- heat capacity of seawater
  rho <- 1025 # kg/m3 <- assumed density of seawater
  
  # calculate midpoint of tag-based min/max temps
  pdt$MidTemp <- (pdt$MaxTemp + pdt$MinTemp) / 2
  
  # get unique time points
  dateVec = parse_date_time(dateVec, '%Y-%m-%d')
  
  udates <- unique(parse_date_time(pdt$Date, orders = '%Y-%m-%d %H%:%M:%S'))
  T <- length(udates)

  if(isotherm != '') iso.def <- TRUE else iso.def <- FALSE
  
  print(paste0('Generating OHC likelihood for ', udates[1], ' through ', udates[length(udates)]))
  
  nc1 =  RNetCDF::open.nc(dir(ohc.dir, full.names = T)[1])
  depth <- RNetCDF::var.get.nc(nc1, 'depth')
  lon <- RNetCDF::var.get.nc(nc1, 'lon')
  lat <- RNetCDF::var.get.nc(nc1, 'lat')
# result will be array of likelihood surfaces
  
  L.ohc <- array(0, dim = c(length(lon), length(lat), length(dateVec)))
  start.t <- Sys.time()
  
# BEGIN PARALLEL STUFF  
  
  print('processing in parallel... ')
  
  # ncores = detectCores()  # should be an input argument
  cl = makeCluster(ncores)
  registerDoParallel(cl, cores = ncores)
  
  ans = foreach(i = 1:T) %dopar%{

    # function not being recognized i nnamespace.. 
  likint3 <- function(w, wsd, minT, maxT){
    midT = (maxT + minT) / 2
    Tsd = (maxT - minT) / 4
    widx = w >= minT & w <= maxT & !is.na(w)
    wdf = data.frame(w = as.vector(w[widx]), wsd = as.vector(wsd[widx]))
    wdf$wsd[is.na(wdf$wsd)] = 0
    # wint = apply(wdf, 1, function(x) pracma::integral(dnorm, minT, maxT, mean = x[1], sd = x[2]))
    wint = apply(wdf, 1, function(x) stats::integrate(stats::dnorm, x[1]-x[2], x[1]+x[2], mean = midT, sd = Tsd * 2)$value) 
    w = w * 0
    w[widx] = wint
    w
  }
    
    time <- as.Date(udates[i])
    pdt.i <- pdt[which(pdt$Date == time),]
    
    # open day's hycom data
    nc <- RNetCDF::open.nc(paste(ohc.dir, ptt,'_', as.Date(time), '.nc', sep=''))
    dat <- RNetCDF::var.get.nc(nc, 'water_temp') * RNetCDF::att.get.nc(nc, 'water_temp', attribute='scale_factor') + 
      RNetCDF::att.get.nc(nc, variable='water_temp', attribute='add_offset')
    
    #extracts depth from tag data for day i
    y <- pdt.i$Depth[!is.na(pdt.i$Depth)] 
    y[y<0] <- 0
    
    #extract temperature from tag data for day i
    x <- pdt.i$MidTemp[!is.na(pdt.i$Depth)]  
    
    # use the which.min
    depIdx = unique(apply(as.data.frame(pdt.i$Depth), 1, FUN=function(x) which.min((x - depth) ^ 2)))
    hycomDep <- depth[depIdx]
    
    if(bathy){
      mask <- dat[,,max(depIdx)]
      mask[is.na(mask)] <- NA
      mask[!is.na(mask)] <- 1
      for(bb in 1:length(depth)){
        dat[,,bb] <- dat[,,bb] * mask
      }
    }
    
    # make predictions based on the regression model earlier for the temperature at standard WOA depth levels for low and high temperature at that depth
    suppressWarnings(
      fit.low <- locfit::locfit(pdt.i$MinTemp ~ pdt.i$Depth)
    )
    suppressWarnings(
      fit.high <- locfit::locfit(pdt.i$MaxTemp ~ pdt.i$Depth)
    )
    n = length(hycomDep)
    
    #suppressWarnings(
    pred.low = stats::predict(fit.low, newdata = hycomDep, se = T, get.data = T)
    #suppressWarnings(
    pred.high = stats::predict(fit.high, newdata = hycomDep, se = T, get.data = T)
    
    
    # data frame for next step
    df = data.frame(low = pred.low$fit - pred.low$se.fit * sqrt(n),
                    high = pred.high$fit + pred.high$se.fit * sqrt(n),
                    depth = hycomDep)
    
    # isotherm is minimum temperature recorded for that time point
    if(iso.def == FALSE) isotherm <- min(df$low, na.rm = T)
    
    # perform tag data integration at limits of model fits
    minT.ohc <- cp * rho * sum(df$low - isotherm, na.rm = T) / 10000
    maxT.ohc <- cp * rho * sum(df$high - isotherm, na.rm = T) / 10000
    
    # Perform hycom integration
    dat[dat<isotherm] <- NA
    dat <- dat - isotherm
    ohc <- cp * rho * apply(dat[,,depIdx], 1:2, sum, na.rm = T) / 10000 
    ohc[ohc == 0] <- NA
    
    # calc sd of OHC
    # focal calc on mean temp and write to sd var
    r = raster::flip(raster::raster(t(ohc)), 2)
    sdx = raster::focal(r, w = matrix(1, nrow = 9, ncol = 9),
                        fun = function(x) stats::sd(x, na.rm = T))
    sdx = t(raster::as.matrix(raster::flip(sdx, 2)))
    
    # compare hycom to that day's tag-based ohc
    lik.ohc <- likint3(ohc, sdx, minT.ohc, maxT.ohc)
    
    # if(i == 1){
    #   # result will be array of likelihood surfaces
    #   L.ohc <- array(0, dim = c(dim(lik.ohc), length(dateVec)))
    # }
    
    # idx <- which(dateVec == as.Date(time))
    # L.ohc[,,idx] = (lik.ohc / max(lik.ohc, na.rm=T)) - 0.2
    # 
  }
  
  stopCluster(cl)
  
  # make index of dates for filling in L.ohc
  
  didx = match(udates, dateVec)
  
  
  # lapply 
  lik.ohc = lapply(ans, function(x) x/max(x, na.rm = T)-0.2)
  
  ii = 1
  for(i in didx){
    L.ohc[,,i] = lik.ohc[[ii]]
    ii = ii+1  
  }

  print(paste('Making final likelihood raster...'))
  
  crs <- "+proj=longlat +datum=WGS84 +ellps=WGS84"
  list.ohc <- list(x = lon-360, y = lat, z = L.ohc)
  ex <- raster::extent(list.ohc)
  L.ohc <- raster::brick(list.ohc$z, xmn=ex[1], xmx=ex[2], ymn=ex[3], ymx=ex[4], transpose=T, crs)
  L.ohc <- raster::flip(L.ohc, direction = 'y')
  
  L.ohc[L.ohc < 0] <- 0
  
  names(L.ohc) = as.character(dateVec)
  
  print(Sys.time() - start.t)
  
  # return ohc likelihood surfaces
  return(L.ohc)
  
}

