## NOTE: this uses multi-stage builds as in https://docs.docker.com/engine/userguide/eng-image/multistage-build/#use-multi-stage-builds
##       Requires Docker v17.05+

## TODO: use ENV to specify a different Apsim release

# Build Container

FROM ubuntu:xenial as builder
MAINTAINER sebxwolf@gmail.com

## Install and configure packages in the common layer
RUN apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 3FA7E0328081BFF6A14DA29AA6A19B38D3D831EF && \
  echo "deb http://download.mono-project.com/repo/ubuntu wheezy/snapshots/4.8.0 main" | tee /etc/apt/sources.list.d/mono-official.list && \
  apt-get update && \
  apt-get -y install tzdata mono-runtime mono-vbnc libmonosgen-2.0-1 libboost-all-dev libxml2 tcl8.5 r-recommended && \
  ln -fs /usr/share/zoneinfo/Africa/Nairobi /etc/localtime && dpkg-reconfigure -f noninteractive tzdata && \
  Rscript -e 'install.packages(c("Rcpp", "RInside", "inline"),repos = "http://cran.us.r-project.org")'

## Install development packages and build Apsim
### svn co sometimes fails with a "Connection reset by peer" error, so we have to force checking out the entire repo
RUN apt-get -y install subversion p7zip p7zip-full g++ gfortran mono-devel libboost-all-dev libxml2-dev tcl8.5-dev \
 && svn co https://github.com/sebxwolf/APSIMClassic apsim || while true; do svn cleanup apsim && svn update apsim; if [ $? -eq 0 ]; then break; fi; done

## Add APSIM repo
#ADD ../APSIMClassic apsim

## These files have been hacked so that the build actually works
### Add CottonPassword.txt file for Cotton Model
# ADD files/CottonPassword.txt /etc/CottonPassword.txt

### Prepended ProcessDataTypesInterface.exe with "mono" instead of calling it directly
#ADD files/rlink-makefile /apsim/trunk/Model/RLink/Makefile.linux
#ADD files/tcllink-makefile /apsim/trunk/Model/TclLink/Makefile

### Disabled building unit tests (requires NUnit v3 for which there is no Debian package and installing from source feels like an overkill)
ADD files/BuildAll.xml /apsim/trunk/Model/Build/BuildAll.xml

RUN cd /apsim/trunk/Model/Build && \
  chmod +x BuildAll.sh && \
  ./BuildAll.sh && \
  export APSIM=/apsim/trunk && \
  cd /apsim/trunk/Release && \
  ./Release.sh

# Runtime Container

FROM ubuntu:xenial
MAINTAINER sebxwolf@gmail.com

## Install and configure packages in the common layer
RUN apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys 3FA7E0328081BFF6A14DA29AA6A19B38D3D831EF && \
  echo "deb http://download.mono-project.com/repo/ubuntu wheezy/snapshots/4.8.0 main" | tee /etc/apt/sources.list.d/mono-official.list && \
  apt-get update && \
  apt-get -y install tzdata mono-runtime mono-vbnc libmonosgen-2.0-1 libboost-all-dev libxml2 tcl8.5 r-recommended && \
  ln -fs /usr/share/zoneinfo/Pacific/Auckland /etc/localtime && dpkg-reconfigure -f noninteractive tzdata && \
  Rscript -e 'install.packages(c("Rcpp", "RInside", "inline"),repos = "http://cran.us.r-project.org")'

## Get built artifact and extract
### /apsim needs to have 755 permissions so that non-privileged users can use the container
COPY --from=builder /apsim/trunk/Release/Apsim*.binaries.LINUX.X86_64.exe /tmp/apsim-release.exe
RUN /tmp/apsim-release.exe -y -o/apsim && \
  rm -f /tmp/apsim-release.exe && \
  chmod 755 apsim

WORKDIR /apsim/Temp/Model
ENV LD_LIBRARY_PATH=/apsim/Temp/Model

## This allows users to call the container directly with the name of the .exe file they want to run (Apsim.exe, ApsimToSim.exe, etc)
ENTRYPOINT ["/usr/bin/mono"]
