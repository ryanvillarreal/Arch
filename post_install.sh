#!/bin/bash

echo "Setting up i3wm and terminal"
yes | sudo pacman -S i3-gaps xorg-server xorg-xinit

echo "Installing common packages"
yes | sudo pacman -S linux-headers dkms 

echo "Installing and configuring UFW"
yes | sudo pacman -S ufw
sudo systemctl enable ufw
sudo systemctl start ufw
sudo ufw enable
sudo ufw default deny incoming
sudo ufw default allow outgoing

echo "Installing and enabling TLP"
sudo pacman -S tlp tlp-rdw
sudo systemctl enable tlp.service
sudo systemctl enable tlp.service
sudo systemctl start tlp.service
sudo systemctl start tlp.service
sudo systemctl enable NetworkManager-dispatcher.service
sudo systemctl mask systemd-rfkill.service
sudo systemctl mask systemd-rfkill.socket

# Modify these for what you need. 
echo "Installing common applications"
echo -en "1\nyes" | sudo pacman -S firefox git openssh vim alacritty upower htop powertop

# Installing NVM and Node.JS for dev stuff
git clone https://aur.archlinux.org/nvm.git
cd nvm
yes | makepkg -si
cd ..
rm -rf nvm
source /usr/share/nvm/init-nvm.sh
nvm install --lts=dubnium


echo "Installing fonts"
yes | sudo pacman -S ttf-droid ttf-opensans ttf-dejavu ttf-liberation ttf-hack ttf-fira-code

# Need to update to grab dot files from this git repository
echo "Installing and setting zsh"
yes | sudo pacman -S zsh
chsh -s /bin/zsh
# wget https://raw.githubusercontent.com/ryanvillarreal/Arch/dots/etc
# wget https://raw.githubusercontent.com/ryanvillarreal/Arch/dots/etc

# Setup oh-my-zsh
# Don't run this line without reading the source to ensure it hasn't been hijacked
#sh -c "$(wget -O- https://raw.githubusercontent.com/robbyrussell/oh-my-zsh/master/tools/install.sh)"
# Modify the theme for Omz
# Modify the plugins for Omz

# Kill bluetooth for safety.  
echo "Blacklisting bluetooth"
sudo touch /etc/modprobe.d/nobt.conf
sudo tee /etc/modprobe.d/nobt.conf << END
blacklist btusb
blacklist bluetooth
END
sudo mkinitcpio -p linux

# should be done at this point
echo "Your setup is ready. You can reboot now!"
