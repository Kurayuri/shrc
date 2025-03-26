#!/bin/bash

# curl -fsSL https://gitee.com/kurayuri/shrc/raw/main/sh_scripts/init.sh | bash -s -- <DEVC_ID>

# sudo adduser kurayuri
# sudo visudo

if [ $# -eq 0 ]; then
  echo "Require DEVC_ID."
  echo "usage: $0 DEVC_ID"
  exit 1  
fi

DEVC_ID=$1
APP_HOME="$HOME/Application"

################################################################
# # apt
sudo apt install tmux
sudo apt install curl
sudo apt install wget

################################################################
# # Anaconda
# https://www.anaconda.com/download#downloads
ANACONDA_VERSION="2024.10-1"
ANACONDA_URL="https://repo.anaconda.com/archive/Anaconda3-${ANACONDA_VERSION}-Linux-x86_64.sh"

ANACONDA_INSTALL_DIR="$APP_HOME/anaconda3"

wget $ANACONDA_URL -O Anaconda3.sh

sh Anaconda3.sh -b -p $ANACONDA_INSTALL_DIR

rm Anaconda3.sh

################################################################
# # ssh
SSH_KEY_DIR="$HOME/.ssh"
SSH_KEY_NAME="id_ed25519"

ssh-keygen -f "$SSH_KEY_DIR/$SSH_KEY_NAME" -N "" -C "Kurayuri@Kurayuri-${DEVC_ID}" -t ed25519

AUTHORIZED_KEYS=$(cat << 'EOF'
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDczlwNt1FQa9oayP2MZOpkzN6Zaj/vlHXkPkm2dFQ9UTOTjgSMqQRLbcFQtwHC35BF5HGEldmoWasz5i8HqS+q3iYtSfnmd4mTMMKkcssLltx2YYL7zyq9sl68nWK7yNgH/jcPj7md2xLp8kPSD5N19nz+Wu66I7vX7LUBZbVFgNHryJRZ6XoqbJUyCY6CnAdiwyL5xKV27/6AccTG1vu7iFPf8Z/PEuU5ticSpmlHGfczGzdAhySV41/SW3kKSVSxP0fNSeaJdeCRKn8mGues1zHXixB1nrMteEufXGDjT8te927vymdezTGeOjZUj0FWaFcwMaNcqUdPk1Iz1fLXtspbO+9ac2+ftEulH7FuAvrvsD8n2fJPqukn4Eav1bmk8oFxOUy0nj+o6jU1FvlHJmiXgbJeJ6j9hnwSn7wIEKkjbSHP5UyAcW2DxDTLVyzgcN5JwHS+efu7ZfGZmGAEpu96zLc27yp0TmgExZijrlM3+sfmwH8+fG0lSD5NtrM= Kurayuri@Kurayuri-PC05
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEjXrZvu1j5oyJTi2emHw7BO9JWPzAgD8QgshcBTWWcd Kurayuri@Kurayuri-PC07
EOF
)
echo "$AUTHORIZED_KEYS" > $SSH_KEY_DIR/authorized_keys


################################################################
# # zsh
ZSHRC="$HOME/.zshrc"
ZSH="$HOME/.oh-my-zsh"

wget https://gitee.com/kurayuri/shrc/raw/main/.shrc -O $HOME/.shrc
sh -c "$(curl -fsSL https://raw.gitmirror.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

sed -i 's/ZSH_THEME="\w\+"/ZSH_THEME="crash"/' $ZSHRC
echo "export DEVC_ID=$DEVC_ID" >> $ZSHRC
echo "export APP_HOME='$APP_HOME'" >> $ZSHRC
echo "export CONDA_HOME='$ANACONDA_INSTALL_DIR'" >> $ZSHRC
echo "source ~/.shrc" >> $ZSHRC
echo 'cni' >> $ZSHRC


theme=$(cat << 'EOF'
PROMPT="%{$fg_bold[green]%}%n@'$DEVC_ID':%{$fg_bold[blue]%}%2c%{$reset_color%}$ "
RPS1="$(git_prompt_info) %{$reset_color%}"


ZSH_THEME_GIT_PROMPT_PREFIX=" %{$fg[yellow]%}("
ZSH_THEME_GIT_PROMPT_SUFFIX=")%{$reset_color%}"
ZSH_THEME_GIT_PROMPT_CLEAN=""
ZSH_THEME_GIT_PROMPT_DIRTY="%{$fg[red]%} ⚡%{$fg[yellow]%}"
EOF
)

echo "$theme" > $ZSH/themes/crash.zsh-theme


################################################################
# # Github CLI
# type -p curl >/dev/null || (sudo apt update && sudo apt install curl -y)
# curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
# && sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
# && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
# && sudo apt update \
# && sudo apt install gh -y

# gh auth login
