FROM ubuntu:14.04

# Install.
RUN \
  apt-get update && \
  apt-get -y upgrade && \
  apt-get install -y build-essential && \
  apt-get install -y software-properties-common && \
  apt-get install -y byobu curl git netcat at htop man unzip vim wget && \
  apt-get install perl make automake autoconf m4 libtool g++ &&\
  git clone https://github.com/Mellanox/sockperf &&\
  cd sockperf &&\
  ./autogen.sh &&\
  ./configure --prefix=/root --enable-test &&\
  make &&\
  make install &&\
  rm -rf /var/lib/apt/lists/*

# Set environment variables.
ENV HOME /root

# Define working directory.
WORKDIR /root

# Define default command.
CMD ["bash"]

