#cp ./ /home/dforeluo/moneroocean-gui/build/xmrig_setup/raw/master/ -rf
find /home/dforeluo/xmrig_setup/ -name '*.sh' -print | xargs dos2unix;
rsync -av --exclude='/home/dforeluo/xmrig_setup/.git/' /home/dforeluo/xmrig_setup/* /home/dforeluo/moneroocean-gui/build/xmrig_setup/raw/master/
