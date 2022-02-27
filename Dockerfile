FROM nvidia/cuda:11.5.1-cudnn8-devel-ubuntu20.04 AS base

# Set up time zone so things don't ask for it
ENV TZ=America/Chicago
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Basic setup
ARG DEBIAN_FRONTEND=noninteractive
RUN apt-get update \
    && apt-get upgrade -y \
    && apt-get install -y locales lsb-release \
    && apt-get install git -y \
    && apt-get install python3 python3-pip python-is-python3 -y \
    && dpkg-reconfigure locales

# Set up a user so we're not just in root
ARG USERNAME=dev
ARG USER_UID=1000
ARG USER_GID=$USER_UID

# Create the user
RUN groupadd --gid $USER_GID $USERNAME \
    && useradd --uid $USER_UID --gid $USER_GID -m $USERNAME \
    && apt-get update \
    && apt-get install -y sudo \
    && echo $USERNAME ALL=\(root\) NOPASSWD:ALL > /etc/sudoers.d/$USERNAME \
    && chmod 0440 /etc/sudoers.d/$USERNAME

# Set the default user and shell
USER $USERNAME
ENV SHELL /bin/bash

# Install ROS
RUN sudo sh -c 'echo "deb http://packages.ros.org/ros/ubuntu $(lsb_release -sc) main" > /etc/apt/sources.list.d/ros-latest.list' \
    && sudo apt-get install curl -y \
    && curl -s https://raw.githubusercontent.com/ros/rosdistro/master/ros.asc | sudo apt-key add - \
    && sudo apt-get update \
    && sudo apt-get install ros-noetic-desktop-full python3-rosdep -y --no-install-recommends \
    && sudo rosdep init \
    && rosdep fix-permissions \
    && rosdep update \
    && echo "source /opt/ros/noetic/setup.bash" >> ~/.bashrc

# Set up deps
RUN python -m pip install --upgrade pip \
    && pip install torch==1.10.2+cu113 torchvision==0.11.3+cu113 torchaudio==0.10.2+cu113 -f https://download.pytorch.org/whl/cu113/torch_stable.html \
    && pip install torchsummary \
    && pip install black

RUN mkdir -p /home/dev/.ssh \
    && echo "IdentityFile ~/.ssh/id" >> /home/dev/.ssh/config \
    && ssh-keyscan github.com >> /home/dev/.ssh/known_hosts
COPY id /home/dev/.ssh
RUN sudo chown dev /home/dev/.ssh/id && chmod 600 /home/dev/.ssh/id

SHELL ["/bin/bash", "-c"]

# Set up amrl things
FROM base AS msgbuilder
RUN cd ~ \
    && git clone git@github.com:ut-amrl/amrl_msgs.git \
    && cd ~/amrl_msgs \
    && source /opt/ros/noetic/setup.bash \
    && export ROS_PACKAGE_PATH=`pwd`:$ROS_PACKAGE_PATH \
    && echo "export ROS_PACKAGE_PATH=`pwd`:\$ROS_PACKAGE_PATH" >> ~/.bashrc \
    && make 

FROM base AS mapbuilder
RUN cd ~ \
    && git clone git@github.com:ut-amrl/amrl_maps.git \
    && cd ~/amrl_maps \
    && echo "export ROS_PACKAGE_PATH=`pwd`:\$ROS_PACKAGE_PATH" >> ~/.bashrc

FROM base as vectordisplaybuilder
COPY --from=msgbuilder /home/dev/amrl_msgs /home/dev/amrl_msgs
RUN cd ~ \
    && git clone git@github.com:ut-amrl/vector_display.git --recurse-submodules \
    && cd ~/vector_display \
    && sudo apt-get install libgoogle-glog-dev libgflags-dev liblua5.1-0-dev qt5-default -y \
    && source /opt/ros/noetic/setup.bash \
    && export ROS_PACKAGE_PATH=`pwd`:/home/dev/amrl_msgs:$ROS_PACKAGE_PATH \
    && echo "export ROS_PACKAGE_PATH=`pwd`:\$ROS_PACKAGE_PATH" >> ~/.bashrc \
    && make

FROM base as enmlbuilder
COPY --from=msgbuilder /home/dev/amrl_msgs /home/dev/amrl_msgs
RUN cd ~ \
    && git clone git@github.com:ut-amrl/enml.git --recurse-submodules \
    && cd ~/enml \
    && sed '${s/$/ -y/}' InstallPackages > InstallPackages-fixed \
    && chmod +x InstallPackages-fixed \
    && ./InstallPackages-fixed \
    && source /opt/ros/noetic/setup.bash \
    && echo "export ROS_PACKAGE_PATH=`pwd`:\$ROS_PACKAGE_PATH" >> ~/.bashrc \
    && export ROS_PACKAGE_PATH=`pwd`:/home/dev/amrl_msgs:$ROS_PACKAGE_PATH \
    && make

FROM base AS amrl
COPY --from=msgbuilder /home/dev/amrl_msgs /home/dev/amrl_msgs
COPY --from=mapbuilder /home/dev/amrl_maps /home/dev/amrl_maps
COPY --from=vectordisplaybuilder /home/dev/vector_display /home/dev/vector_display
COPY --from=enmlbuilder /home/dev/enml /home/dev/enml
RUN echo "export ROS_PACKAGE_PATH=/home/dev/amrl_msgs:/home/dev/amrl_maps:/home/dev/vector_display:/home/dev/enml:\$ROS_PACKAGE_PATH" >> ~/.bashrc
