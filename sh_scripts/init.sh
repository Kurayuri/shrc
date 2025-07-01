#!/bin/bash

# curl -fsSL https://gitee.com/kurayuri/shrc/raw/main/sh_scripts/init.sh | bash -s -- <DEVC_ID>

# sudo adduser kurayuri
# sudo visudo

if [ $# -eq 0 ]; then
  echo "Require DEVC_ID."
  echo "usage: $0 DEVC_ID"
  exit 1  
fi

CONDA_TYPE="miniconda"
POSITIONAL=()
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    -conda)
      CONDA_TYPE="$2"
      shift # past argument
      shift # past value
      ;;
    *)
      POSITIONAL+=("$1") # save positional arg
      shift
      ;;
  esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters

echo "Conda type: $CONDA_TYPE"

DEVC_ID=$1
APP_HOME="$HOME/Application"

################################################################
# # apt
sudo apt update
sudo apt install -y tmux zsh curl wget git git-lfs net-tools

################################################################
# # Anaconda
# https://www.anaconda.com/download#downloads
ANACONDA_VERSION="2024.10-1"
ANACONDA_URL="https://repo.anaconda.com/archive/Anaconda3-${ANACONDA_VERSION}-Linux-x86_64.sh"
MINICONDA_URL="https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh"

CONDA_URL=""

if [ "$CONDA_TYPE" == "anaconda" ]; then
  CONDA_URL=$ANACONDA_URL
elif [ "$CONDA_TYPE" == "miniconda" ]; then
  CONDA_URL=$MINICONDA_URL
fi

if [ -n "$CONDA_URL" ]; then
  ANACONDA_INSTALL_DIR="$APP_HOME/anaconda3"
  if [ -f "Anaconda3.sh" ]; then
    LOCAL_SIZE=$(stat -c%s "Anaconda3.sh")
    REMOTE_SIZE=$(wget --spider --server-response $CONDA_URL 2>&1 | awk '/Content-Length/ {print $2}' | tail -1)
  else
    LOCAL_SIZE=0
    REMOTE_SIZE=1
  fi
  if [ "$LOCAL_SIZE" != "$REMOTE_SIZE" ]; then
    wget $CONDA_URL -O Anaconda3.sh
  fi

  sh Anaconda3.sh -b -p $ANACONDA_INSTALL_DIR

  rm Anaconda3.sh
fi
################################################################
# # ssh
SSH_KEY_DIR="$HOME/.ssh"
SSH_KEY_NAME="id_ed25519"

if [ ! -f "$SSH_KEY_DIR/$SSH_KEY_NAME" ]; then
  ssh-keygen -f "$SSH_KEY_DIR/$SSH_KEY_NAME" -N "" -C "Kurayuri@Kurayuri-${DEVC_ID}" -t ed25519
else
  echo "Skip: SSH key already exists: $SSH_KEY_DIR/$SSH_KEY_NAME"
fi

AUTHORIZED_KEYS=$(cat << 'EOF'
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDczlwNt1FQa9oayP2MZOpkzN6Zaj/vlHXkPkm2dFQ9UTOTjgSMqQRLbcFQtwHC35BF5HGEldmoWasz5i8HqS+q3iYtSfnmd4mTMMKkcssLltx2YYL7zyq9sl68nWK7yNgH/jcPj7md2xLp8kPSD5N19nz+Wu66I7vX7LUBZbVFgNHryJRZ6XoqbJUyCY6CnAdiwyL5xKV27/6AccTG1vu7iFPf8Z/PEuU5ticSpmlHGfczGzdAhySV41/SW3kKSVSxP0fNSeaJdeCRKn8mGues1zHXixB1nrMteEufXGDjT8te927vymdezTGeOjZUj0FWaFcwMaNcqUdPk1Iz1fLXtspbO+9ac2+ftEulH7FuAvrvsD8n2fJPqukn4Eav1bmk8oFxOUy0nj+o6jU1FvlHJmiXgbJeJ6j9hnwSn7wIEKkjbSHP5UyAcW2DxDTLVyzgcN5JwHS+efu7ZfGZmGAEpu96zLc27yp0TmgExZijrlM3+sfmwH8+fG0lSD5NtrM= Kurayuri@Kurayuri-PC05
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEjXrZvu1j5oyJTi2emHw7BO9JWPzAgD8QgshcBTWWcd Kurayuri@Kurayuri-PC07
EOF
)
echo "$AUTHORIZED_KEYS" > $SSH_KEY_DIR/authorized_keys

################################################################
# # zsh
echo "Installing Oh My Zsh..."
ZSHRC="$HOME/.zshrc"
ZSH="$HOME/.oh-my-zsh"

wget https://gitee.com/kurayuri/shrc/raw/main/.shrc -O $HOME/.shrc
sh -c "$(curl -fsSL https://raw.gitmirror.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
sed -i 's/ZSH_THEME="\w\+"/ZSH_THEME="crash"/' $ZSHRC

theme=$(cat << 'EOF'
PROMPT="%{$fg_bold[green]%}%n@<${DEVC_ID}>:%{$fg_bold[blue]%}%2c%{$reset_color%}$ "
RPS1="$(git_prompt_info) %{$reset_color%}"


ZSH_THEME_GIT_PROMPT_PREFIX=" %{$fg[yellow]%}("
ZSH_THEME_GIT_PROMPT_SUFFIX=")%{$reset_color%}"
ZSH_THEME_GIT_PROMPT_CLEAN=""
ZSH_THEME_GIT_PROMPT_DIRTY="%{$fg[red]%} ⚡%{$fg[yellow]%}"
EOF
)
echo "$theme" > $ZSH/themes/crash.zsh-theme
sed -i "s|<\${DEVC_ID}>|${DEVC_ID}|g" $ZSH/themes/crash.zsh-theme

# sed -i "1i export DEVC_ID=$DEVC_ID" $ZSHRC
echo "export APP_HOME='$APP_HOME'" >> $ZSHRC
echo "export CONDA_HOME='$ANACONDA_INSTALL_DIR'" >> $ZSHRC
echo "source ~/.shrc" >> $ZSHRC
echo 'cni' >> $ZSHRC

BASHRC="$HOME/.bashrc"
echo "source ~/.shrc" >> $BASHRC

################################################################
# # Github CLI
# type -p curl >/dev/null || (sudo apt update && sudo apt install curl -y)
# curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
# && sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
# && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
# && sudo apt update \
# && sudo apt install gh -y

# gh auth login
