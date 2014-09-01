#!/bin/sh -e
#
# Copyright (c) 2014 Robert Nelson <robertcnelson@gmail.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

export LC_ALL=C

chromium_release="chromium-33.0.1750.117"
u_boot_release="v2014.07"
cloud9_pkg="c9v3-beaglebone-build-2-20140414.tar.gz"

#contains: rfs_username, release_date
if [ -f /etc/rcn-ee.conf ] ; then
	. /etc/rcn-ee.conf
fi

if [ -f /etc/oib.project ] ; then
	. /etc/oib.project
fi

is_this_qemu () {
	unset warn_qemu_will_fail
	if [ -f /usr/bin/qemu-arm-static ] ; then
		warn_qemu_will_fail=1
	fi
}

qemu_warning () {
	if [ "${warn_qemu_will_fail}" ] ; then
		echo "Log: (chroot) Warning, qemu can fail here... (run on real armv7l hardware for production images)"
		echo "Log: (chroot): [${qemu_command}]"
	fi
}

git_clone () {
	mkdir -p ${git_target_dir} || true
	qemu_command="git clone ${git_repo} ${git_target_dir} --depth 1 || true"
	qemu_warning
	git clone ${git_repo} ${git_target_dir} --depth 1 || true
	sync
	echo "${git_target_dir} : ${git_repo}" >> /opt/source/list.txt
}

git_clone_branch () {
	mkdir -p ${git_target_dir} || true
	qemu_command="git clone -b ${git_branch} ${git_repo} ${git_target_dir} --depth 1 || true"
	qemu_warning
	git clone -b ${git_branch} ${git_repo} ${git_target_dir} --depth 1 || true
	sync
	echo "${git_target_dir} : ${git_repo}" >> /opt/source/list.txt
}

git_clone_full () {
	mkdir -p ${git_target_dir} || true
	qemu_command="git clone ${git_repo} ${git_target_dir} || true"
	qemu_warning
	git clone ${git_repo} ${git_target_dir} || true
	sync
	echo "${git_target_dir} : ${git_repo}" >> /opt/source/list.txt
}

install_picky_packages () {
	#Setting up trousers (0.3.9-3+wheezy1) ...
	#dpkg: error processing trousers (--configure):
	# subprocess installed post-installation script returned error exit status 2
	#dpkg: dependency problems prevent configuration of tpm-tools:
	# tpm-tools depends on trousers; however:
	#  Package trousers is not configured yet.
	#
	#dpkg: error processing tpm-tools (--configure):
	# dependency problems - leaving unconfigured
	#Errors were encountered while processing:
	# trousers
	# tpm-tools

	pkg="trousers"
	echo "Installing picky package: ${pkg}"
	apt-get -y --force-yes install ${pkg}
	apt-get clean

	pkg="tpm-tools"
	echo "Installing picky package: ${pkg}"
	apt-get -y --force-yes install ${pkg}
	apt-get clean
}

setup_system () {
	#For when sed/grep/etc just gets way to complex...
	cd /
	if [ -f /opt/scripts/mods/debian-add-sbin-usr-sbin-to-default-path.diff ] ; then
		if [ -f /usr/bin/patch ] ; then
			patch -p1 < /opt/scripts/mods/debian-add-sbin-usr-sbin-to-default-path.diff
		fi
	fi

	if [ -f /lib/systemd/system/serial-getty@.service ] ; then
		cp /lib/systemd/system/serial-getty@.service /etc/systemd/system/serial-getty@ttyGS0.service
		ln -s /etc/systemd/system/serial-getty@ttyGS0.service /etc/systemd/system/getty.target.wants/serial-getty@ttyGS0.service

		echo "" >> /etc/securetty
		echo "#USB Gadget Serial Port" >> /etc/securetty
		echo "ttyGS0" >> /etc/securetty
	fi
}

setup_desktop () {
	if [ -d /etc/X11/ ] ; then
		wfile="/etc/X11/xorg.conf"
		echo "Section \"Monitor\"" > ${wfile}
		echo "        Identifier      \"Builtin Default Monitor\"" >> ${wfile}
		echo "EndSection" >> ${wfile}
		echo "" >> ${wfile}
		echo "Section \"Device\"" >> ${wfile}
		echo "        Identifier      \"Builtin Default fbdev Device 0\"" >> ${wfile}

#		echo "        Driver          \"modesetting\"" >> ${wfile}
		echo "        Driver          \"fbdev\"" >> ${wfile}

		echo "EndSection" >> ${wfile}
		echo "" >> ${wfile}
		echo "Section \"Screen\"" >> ${wfile}
		echo "        Identifier      \"Builtin Default fbdev Screen 0\"" >> ${wfile}
		echo "        Device          \"Builtin Default fbdev Device 0\"" >> ${wfile}
		echo "        Monitor         \"Builtin Default Monitor\"" >> ${wfile}
		echo "        DefaultDepth    16" >> ${wfile}
		echo "EndSection" >> ${wfile}
		echo "" >> ${wfile}
		echo "Section \"ServerLayout\"" >> ${wfile}
		echo "        Identifier      \"Builtin Default Layout\"" >> ${wfile}
		echo "        Screen          \"Builtin Default fbdev Screen 0\"" >> ${wfile}
		echo "EndSection" >> ${wfile}
	fi

	wfile="/etc/lightdm/lightdm.conf"
	if [ -f ${wfile} ] ; then
		sed -i -e 's:#autologin-user=:autologin-user='$rfs_username':g' ${wfile}
		sed -i -e 's:#autologin-session=UNIMPLEMENTED:autologin-session='$rfs_default_desktop':g' ${wfile}
		if [ -f /opt/scripts/3rdparty/xinput_calibrator_pointercal.sh ] ; then
			sed -i -e 's:#display-setup-script=:display-setup-script=/opt/scripts/3rdparty/xinput_calibrator_pointercal.sh:g' ${wfile}
		fi
	fi

	if [ ! "x${rfs_desktop_background}" = "x" ] ; then
		cp -v "${rfs_desktop_background}" /opt/desktop-background.jpg

		mkdir -p /home/${rfs_username}/.config/pcmanfm/LXDE/ || true
		wfile="/home/${rfs_username}/.config/pcmanfm/LXDE/pcmanfm.conf"
		echo "[desktop]" > ${wfile}
		echo "wallpaper_mode=1" >> ${wfile}
		echo "wallpaper=/opt/desktop-background.jpg" >> ${wfile}
		chown -R ${rfs_username}:${rfs_username} /home/${rfs_username}/.config/
	fi

	#Disable dpms mode and screen blanking
	#Better fix for missing cursor
	wfile="/home/${rfs_username}/.xsessionrc"
	echo "#!/bin/sh" > ${wfile}
	echo "" >> ${wfile}
	echo "xset -dpms" >> ${wfile}
	echo "xset s off" >> ${wfile}
	echo "xsetroot -cursor_name left_ptr" >> ${wfile}
	chown -R ${rfs_username}:${rfs_username} ${wfile}

	#Disable LXDE's screensaver on autostart
	if [ -f /etc/xdg/lxsession/LXDE/autostart ] ; then
		cat /etc/xdg/lxsession/LXDE/autostart | grep -v xscreensaver > /tmp/autostart
		mv /tmp/autostart /etc/xdg/lxsession/LXDE/autostart
		rm -rf /tmp/autostart || true
	fi

	wfile="/etc/udev/rules.d/70-persistent-net.rules"
	echo "" > ${wfile}
	echo "# Auto generated by RootStock-NG: setup_sdcard.sh" >> ${wfile}
	echo "# udevadm info -q all -p /sys/class/net/eth0 --attribute-walk" >> ${wfile}
	echo "" >> ${wfile}
	echo "# BeagleBone: net device ()" >> ${wfile}
	echo "SUBSYSTEM==\"net\", ACTION==\"add\", DRIVERS==\"?*\", ATTR{dev_id}==\"0x0\", ATTR{type}==\"1\", KERNEL==\"eth*\", NAME=\"eth0\"" >> ${wfile}
	echo "" >> ${wfile}

	echo "BeagleBoard.org BeagleBone Debian Image ${release_date}" > /etc/dogtag

	#echo "CAPE=cape-bone-proto" >> /etc/default/capemgr

	#root password is blank, so remove useless application as it requires a password.
	if [ -f /usr/share/applications/gksu.desktop ] ; then
		rm -f /usr/share/applications/gksu.desktop || true
	fi

	#Add Website for Help:
	echo "Support/FAQ: http://elinux.org/Beagleboard:BeagleBoneBlack_Debian" >> /etc/issue
	echo "" >> /etc/issue

	echo "" >> /etc/issue.net
	cat /etc/dogtag >> /etc/issue.net
	echo "" >> /etc/issue.net
	echo "Support/FAQ: http://elinux.org/Beagleboard:BeagleBoneBlack_Debian" >> /etc/issue.net

	if [ -f /etc/ssh/sshd_config ] ; then
		sed -i -e 's:#Banner:Banner:g' /etc/ssh/sshd_config
	fi

	#lxterminal doesnt reference .profile by default, so call via loginshell and start bash
	if [ -f /usr/bin/lxterminal ] ; then
		if [ -f /usr/share/applications/lxterminal.desktop ] ; then
			sed -i -e 's:Exec=lxterminal:Exec=lxterminal -l -e bash:g' /usr/share/applications/lxterminal.desktop
			sed -i -e 's:TryExec=lxterminal -l -e bash:TryExec=lxterminal:g' /usr/share/applications/lxterminal.desktop
		fi
	fi
}

cleanup_npm_cache () {
	if [ -d /root/tmp/ ] ; then
		rm -rf /root/tmp/ || true
	fi

	if [ -d /root/.npm ] ; then
		rm -rf /root/.npm || true
	fi
}

install_node_pkgs () {
	if [ -f /usr/bin/npm ] ; then
		echo "Installing npm packages"
		echo "debug: node: [`node --version`]"
		echo "debug: npm: [`npm --version`]"

		echo "NODE_PATH=/usr/local/lib/node_modules" > /etc/default/node
		echo "export NODE_PATH=/usr/local/lib/node_modules" > /etc/profile.d/node.sh
		chmod 755 /etc/profile.d/node.sh

		#debug
		#echo "debug: npm config ls -l (before)"
		#echo "--------------------------------"
		#npm config ls -l
		#echo "--------------------------------"

		#fix npm in chroot.. (did i mention i hate npm...)
		if [ ! -d /root/.npm ] ; then
			mkdir -p /root/.npm
		fi
		npm config set cache /root/.npm
		npm config set group 0
		npm config set init-module /root/.npm-init.js

		if [ ! -d /root/tmp ] ; then
			mkdir -p /root/tmp
		fi
		npm config set tmp /root/tmp
		npm config set user 0
		npm config set userconfig /root/.npmrc

		#http://blog.npmjs.org/post/78085451721/npms-self-signed-certificate-is-no-more
		#The cause: npm no longer supports its self-signed certificates.
		npm config set ca ""

		#echo "debug: npm config ls -l (after)"
		#echo "--------------------------------"
		#npm config ls -l
		#echo "--------------------------------"

		echo "Installing bonescript"
		TERM=dumb npm install -g bonescript --arch=armhf
		if [ -f /usr/local/lib/node_modules/bonescript/server.js ] ; then
			sed -i -e 's:/usr/share/bone101:/var/lib/cloud9:g' /usr/local/lib/node_modules/bonescript/server.js
		fi

		#Cloud9:
		echo "Installing winston"
		TERM=dumb npm install -g winston --arch=armhf

		cleanup_npm_cache
		sync

		cd /opt/
		mkdir -p /opt/cloud9/
		wget https://rcn-ee.net/pkgs/c9v3/${cloud9_pkg}
		if [ -f /opt/${cloud9_pkg} ] ; then
			tar xf ${cloud9_pkg} -C /opt/cloud9/
			rm -rf ${cloud9_pkg} || true

			#Fixme: archive structure changed in c9v3-beaglebone-build-2-20140414...
			if [ -d /opt/cloud9/c9v3-beaglebone-build-2-20140414 ] ; then
				mv /opt/cloud9/c9v3-beaglebone-build-2-20140414/* /opt/cloud9/
				rm -rf /opt/cloud9/c9v3-beaglebone-build-2-20140414 || true
			fi

			chown -R ${rfs_username}:${rfs_username} /opt/cloud9/

			if [ -f /opt/cloud9/install.sh ] ; then
				cd /opt/cloud9/
				/bin/sh ./install.sh
				cd -
			fi

			#if [ -f /opt/scripts/mods/cloud9-systemd-fix.diff ] ; then
			#	cd /opt/cloud9/
			#	patch -p1 < /opt/scripts/mods/cloud9-systemd-fix.diff
			#	cd /opt/
			#fi
		fi

		git_repo="https://github.com/beagleboard/bone101"
		git_target_dir="/var/lib/cloud9"
		git_clone
		if [ -f ${git_target_dir}/.git/config ] ; then
			chown -R ${rfs_username}:${rfs_username} ${git_target_dir}
			cd ${git_target_dir}/

			wfile="/lib/systemd/system/bonescript.socket"
			echo "[Socket]" > ${wfile}
			echo "ListenStream=80" >> ${wfile}
			echo "" >> ${wfile}
			echo "[Install]" >> ${wfile}
			echo "WantedBy=sockets.target" >> ${wfile}

			wfile="/lib/systemd/system/bonescript.service"
			echo "[Unit]" > ${wfile}
			echo "Description=Bonescript server" >> ${wfile}
			echo "" >> ${wfile}
			echo "[Service]" >> ${wfile}
			echo "WorkingDirectory=/usr/local/lib/node_modules/bonescript" >> ${wfile}
			echo "ExecStart=/usr/bin/node server.js" >> ${wfile}
			echo "SyslogIdentifier=bonescript" >> ${wfile}

			systemctl enable bonescript.socket

			wfile="/lib/systemd/system/bonescript-autorun.service"
			echo "[Unit]" > ${wfile}
			echo "Description=Bonescript autorun" >> ${wfile}
			echo "ConditionPathExists=|/var/lib/cloud9" >> ${wfile}
			echo "" >> ${wfile}
			echo "[Service]" >> ${wfile}
			echo "WorkingDirectory=/usr/local/lib/node_modules/bonescript" >> ${wfile}
			echo "EnvironmentFile=/etc/default/node" >> ${wfile}
			echo "ExecStart=/usr/bin/node autorun.js" >> ${wfile}
			echo "SyslogIdentifier=bonescript-autorun" >> ${wfile}
			echo "" >> ${wfile}
			echo "[Install]" >> ${wfile}
			echo "WantedBy=multi-user.target" >> ${wfile}

			systemctl enable bonescript-autorun.service

			#bonescript.socket takes over port 80, so shove apache/etc to 8080:
			if [ -f /etc/apache2/ports.conf ] ; then
				sed -i -e 's:80:8080:g' /etc/apache2/ports.conf
			fi
			if [ -f /etc/apache2/sites-enabled/000-default ] ; then
				sed -i -e 's:80:8080:g' /etc/apache2/sites-enabled/000-default
			fi
			if [ -f /var/www/index.html ] ; then
				rm -rf /var/www/index.html || true
			fi
		fi
	fi
}

install_pip_pkgs () {
	if [ -f /usr/bin/pip ] ; then
		echo "Installing pip packages"

		#debian@beaglebone:~$ pip install Adafruit_BBIO
		#Downloading/unpacking Adafruit-BBIO
		#  Downloading Adafruit_BBIO-0.0.19.tar.gz
		#  Running setup.py egg_info for package Adafruit-BBIO
		#    The required version of distribute (>=0.6.45) is not available,
		#    and can't be installed while this script is running. Please
		#    install a more recent version first, using
		#    'easy_install -U distribute'.
		#
		#    (Currently using distribute 0.6.24dev-r0 (/usr/lib/python2.7/dist-packages))
		#    Complete output from command python setup.py egg_info:
		#    The required version of distribute (>=0.6.45) is not available,
		#
		#and can't be installed while this script is running. Please
		#
		#install a more recent version first, using
		#
		#'easy_install -U distribute'.
		#
		#(Currently using distribute 0.6.24dev-r0 (/usr/lib/python2.7/dist-packages))

		easy_install -U distribute
		pip install Adafruit_BBIO
	fi
}

install_gem_pkgs () {
	if [ -f /usr/bin/gem ] ; then
		echo "Installing gem packages"
		gem install beaglebone
	fi
}

install_git_repos () {
	git_repo="https://github.com/prpplague/Userspace-Arduino"
	git_target_dir="/opt/source/Userspace-Arduino"
	git_clone

	git_repo="https://github.com/cdsteinkuehler/beaglebone-universal-io.git"
	git_target_dir="/opt/source/beaglebone-universal-io"
	git_clone
	if [ -f ${git_target_dir}/.git/config ] ; then
		if [ -f ${git_target_dir}/config-pin ] ; then
			ln -s ${git_target_dir}/config-pin /usr/local/bin/
		fi
	fi

	git_repo="https://github.com/strahlex/BBIOConfig.git"
	git_target_dir="/opt/source/BBIOConfig"
	git_clone

	git_repo="https://github.com/prpplague/fb-test-app.git"
	git_target_dir="/opt/source/fb-test-app"
	git_clone
	if [ -f ${git_target_dir}/.git/config ] ; then
		cd ${git_target_dir}/
		if [ -f /usr/bin/make ] ; then
			make
		fi
	fi

	git_repo="https://github.com/biocode3D/prufh.git"
	git_target_dir="/opt/source/prufh"
	git_clone
	if [ -f ${git_target_dir}/.git/config ] ; then
		cd ${git_target_dir}/
		if [ -f /usr/bin/make ] ; then
			make LIBDIR_APP_LOADER=/usr/lib/ INCDIR_APP_LOADER=/usr/include
		fi
	fi

	git_repo="https://github.com/alexanderhiam/PyBBIO.git"
	git_target_dir="/opt/source/PyBBIO"
	git_clone
	if [ -f ${git_target_dir}/.git/config ] ; then
		cd ${git_target_dir}/
		sed -i "s/PLATFORM = ''/PLATFORM = 'BeagleBone >=3.8'/g" setup.py
		python setup.py install
	fi

	git_repo="https://github.com/omapconf/omapconf.git"
	git_target_dir="/opt/source/omapconf"
	git_clone
	if [ -f ${git_target_dir}/.git/config ] ; then
		cd ${git_target_dir}/
		if [ -f /usr/bin/make ] ; then
			make CROSS_COMPILE= DESTDIR=/usr/local/bin/ install
		fi
	fi

	git_repo="https://github.com/RobertCNelson/dtb-rebuilder.git"
	git_branch="3.14-ti"
	git_target_dir="/opt/source/dtb-${git_branch}"
	git_clone_branch
}

install_build_pkgs () {
	cd /opt/
	if [ -f /usr/bin/xz ] ; then
		wget https://rcn-ee.net/pkgs/chromium/${chromium_release}-armhf.tar.xz
		if [ -f /opt/${chromium_release}-armhf.tar.xz ] ; then
			tar xf ${chromium_release}-armhf.tar.xz -C /
			rm -rf ${chromium_release}-armhf.tar.xz || true
			echo "${chromium_release} : https://rcn-ee.net/pkgs/chromium/${chromium_release}.tar.xz" >> /opt/source/list.txt

			#link Chromium to /usr/bin/x-www-browser
			update-alternatives --install /usr/bin/x-www-browser x-www-browser /usr/bin/chromium 200
		fi
	fi
}

install_kernel_modules () {
	dist=${deb_codename}
	arch=${deb_arch}
	mirror="https://rcn-ee.net/deb"
	latest_kernel=$(ls /boot/ | grep vmlinuz | grep bone | head -n 1 | awk -F "vmlinuz-" '{print $2}' || true)

	if [ ! "x${latest_kernel}" = "x" ] ; then

		if [ -f /etc/rcn-ee.conf ] ; then
			. /etc/rcn-ee.conf

			if [ "x${third_party_modules}" = "xenable" ] ; then
				echo "Debug: third_party_modules enabled in /etc/rcn-ee.conf"

				cd /tmp/
				if [ -f /tmp/index.html ] ; then
					rm -f /tmp/index.html || true
				fi

				wget ${mirror}/${dist}-${arch}/v${latest_kernel}/
				unset thirdparty_file
				thirdparty_file=$(cat /tmp/index.html | grep thirdparty | head -n 1)
				thirdparty_file=$(echo ${thirdparty_file} | awk -F "\"" '{print $2}')
				rm -f /tmp/index.html || true

				if [ "x${thirdparty_file}" = "xthirdparty" ] ; then

					if [ -f /tmp/thirdparty ] ; then
						rm -rf /tmp/thirdparty || true
					fi

					wget ${mirror}/${dist}-${arch}/v${latest_kernel}/thirdparty

					if [ -f /tmp/thirdparty ] ; then
						/bin/sh /tmp/thirdparty
						depmod ${latest_kernel} -a
						update-initramfs -uk ${latest_kernel}
						rm -rf /tmp/thirdparty || true
						echo "Debug: third party kernel modules now installed."
					fi

				fi
				cd /
			fi
		fi

	fi
}

other_source_links () {
	rcn_https="https://raw.githubusercontent.com/RobertCNelson/Bootloader-Builder/master/patches"

	mkdir -p /opt/source/u-boot_${u_boot_release}/
	cd /opt/source/u-boot_${u_boot_release}/

	wget ${rcn_https}/v2014.07/upstream/0001-Add-option-r-to-env-import-to-allow-import-of-text-f.patch
	wget ${rcn_https}/v2014.07/upstream/0002-am335x_evm-handle-import-of-environments-in-files-wi.patch
	wget ${rcn_https}/${u_boot_release}/0001-am335x_evm-uEnv.txt-bootz-n-fixes.patch

	echo "0001-Add-option-r-to-env-import-to-allow-import-of-text-f.patch" > patch.order
	echo "0002-am335x_evm-handle-import-of-environments-in-files-wi.patch" >> patch.order
	echo "0001-am335x_evm-uEnv.txt-bootz-n-fixes.patch" >> patch.order

	cd /
	echo "u-boot_${u_boot_release} : /opt/source/u-boot_${u_boot_release}" >> /opt/source/list.txt

	echo "MT7601: /etc/Wireless/RT2870/RT2870STA.dat" >> /opt/source/list.txt
	echo "MT7601: MODULES/kernel/drivers/net/wireless/mt7601Usta.ko" >> /opt/source/list.txt
	echo "MT7601: https://rcn-ee.net/deb/thirdparty/MT7601/DPO_MT7601U_LinuxSTA_3.0.0.4_20130913.tar.bz2" >> /opt/source/list.txt
}

unsecure_root () {
	root_password=$(cat /etc/shadow | grep root | awk -F ':' '{print $2}')
	sed -i -e 's:'$root_password'::g' /etc/shadow

	if [ -f /etc/ssh/sshd_config ] ; then
		#Make ssh root@beaglebone work..
		sed -i -e 's:PermitEmptyPasswords no:PermitEmptyPasswords yes:g' /etc/ssh/sshd_config
		sed -i -e 's:UsePAM yes:UsePAM no:g' /etc/ssh/sshd_config
	fi

	if [ -f /etc/sudoers ] ; then
		#Don't require password for sudo access
		echo "${rfs_username}  ALL=NOPASSWD: ALL" >>/etc/sudoers
	fi
}

is_this_qemu

#install_picky_packages

setup_system
setup_desktop

install_node_pkgs
install_pip_pkgs
install_gem_pkgs
if [ -f /usr/bin/git ] ; then
	install_git_repos
fi
install_build_pkgs
install_kernel_modules
other_source_links
unsecure_root
#
