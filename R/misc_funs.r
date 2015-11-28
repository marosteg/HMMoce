## Setup the discrete spatial grid for the HMM
setup.grid <- function(light){
  ## Setup the discrete spatial grid for the HMM
  
  T <- length(light$Longitude)
  
  # Find longitude extents
  il <- floor(min(light$Longitude))
  al <- ceiling(max(light$Longitude))
  lx <- 0.1*(al-il)
  lonl <- il - lx
  lonu <- al + lx
  lo.out <- 4 * (lonu - lonl)
  
  # Find latitude extents
  ila <- floor(min(light$Latitude))
  ala <- ceiling(max(light$Latitude))
  ly <- 0.1*(ala-ila)
  latl <- ila - ly
  latu <- ala + ly
  la.out <- 4 * (latu - latl)
  
  #  latvec <- seq(0,90)
  #  lats <- rep(0,T)
  #  for(t in 1:T){
  #    time <- date2time(lsst$date[t])
  #    #time <- as.numeric(strftime(lsst$date[t],format='%j'))
  #    ssts <- sstdb(time,lsst$lon[t],latvec)
  #    lats[t] <- latvec[sum(lsst$sst[t]<ssts)]
  #  }
  #  lx <- 0.1*(max(lats)-min(lats))
  #  latl <- min(lats) - lx
  #  latu <- max(lats) + lx
  
  # Create grid
  lo <- seq(lonl, lonu, length.out = lo.out)
  la <- seq(latl, latu, length.out = la.out)
  g <- meshgrid(lo, la)
  dlo <- lo[2]-lo[1]
  dla <- la[2]-la[1]
  
  list(lon=g$X,lat=g$Y,dlo=dlo,dla=dla)
}

meshgrid <- function(x,y){
  Y <- repmat(as.matrix(y),1,length(x))
  X <- repmat(t(as.matrix(x)),length(y),1)
  list(X=X,Y=Y)
}

repmat <- function(X,m,n){
  mx = dim(X)[1]
  nx = dim(X)[2]
  matrix(t(matrix(X,mx,nx*n)),mx*m,nx*n,byrow=T)
}