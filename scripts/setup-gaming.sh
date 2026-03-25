#!/bin/bash

# Setup for gaming system deployment with RetroPie and Ryujinx

# Update system packages
sudo apt update && sudo apt upgrade -y

# Install dependencies
sudo apt install -y git

# Clone RetroPie scripts
git clone --depth=1 https://github.com/RetroPie/RetroPie-Setup.git /opt/retropie

# Run RetroPie setup script
cd /opt/retropie && sudo ./retropie_setup.sh

# Install Ryujinx
sudo add-apt-repository ppa:ryujinx/ryujinx
sudo apt update
sudo apt install -y ryujinx

# Provide instructions
echo "Installation complete! Launch RetroPie and Ryujinx to get started."