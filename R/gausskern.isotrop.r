# no final standardisation by the sum
# used to design a pseudo optimal size for the kernel based on sigma 
# the idea is to keep at least 99% of the diffusion 
gausskern.isotrop=function (siz, sigma, muadv = 0,ratio.xy) {
  
  # x longitude
  sizx=siz/ratio.xy
  sigmax=siz/ratio.xy
  if (round(sizx) < 1) sizx = 1
  x = 1:round(sizx)
  mux = c(mean(x), mean(x)) + muadv/ratio.xy
  fx = exp(-0.5 * ((x - mux[1])/sigmax)^2)/sqrt((2 * pi) * sigmax**2) 
  fx[!is.finite(fx)] = 0
  
  # y latitude
  sizy=siz
  sigmay=siz
  if (round(sizy) < 1) sizy = 1
  y = 1:round(sizy)
  muy = c(mean(y), mean(y)) + muadv
  fy = exp(-0.5 * ((y - muy[2])/sigmay)^2)/sqrt((2 * pi) * sigmay**2) 
  fy[!is.finite(fy)] = 0
  
  # kernel
  kern = (fx %*% t(fy))
  kern = kern/(sum(kern, na.rm = T))#;kern
  kern[is.nan(kern)] = 0
  kern
}