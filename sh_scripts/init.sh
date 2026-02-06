#!/bin/bash

# curl -fsSL https://gitee.com/kurayuri/shrc/raw/main/sh_scripts/init.sh | bash -s -- <DEVC_ID> --exec all --conda-type miniconda

# sudo adduser kurayuri
# sudo visudo

# --- Functions ---

install_apt_packages() {
  echo "--- Installing apt packages ---"
  if [ "$(id -u)" -eq 0 ]; then
    SUDO=""
  else
    SUDO="sudo"
  fi

  $SUDO apt update
  $SUDO apt install -y tmux zsh curl wget git git-lfs net-tools psmisc
}

install_conda() {
  echo "--- Installing Conda ($CONDA_TYPE) ---"
  # https://www.anaconda.com/download#downloads
  ANACONDA_VERSION="2025.06-1"
  OS_TYPE=$(uname -s)
  ARCH_TYPE=$(uname -m)
  ANACONDA_URL="https://repo.anaconda.com/archive/Anaconda3-${ANACONDA_VERSION}-${OS_TYPE}-${ARCH_TYPE}.sh"
  MINICONDA_URL="https://repo.anaconda.com/miniconda/Miniconda3-latest-${OS_TYPE}-${ARCH_TYPE}.sh"

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
}

setup_ssh() {
  echo "--- Setting up SSH ---"
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

if [ ! -f "$SSH_KEY_DIR/authorized_keys" ]; then
  echo "$AUTHORIZED_KEYS" > "$SSH_KEY_DIR/authorized_keys"
else
  existing_keys=$(cat "$SSH_KEY_DIR/authorized_keys")
  echo "$AUTHORIZED_KEYS" | while IFS= read -r key; do
    if [ -n "$key" ] && ! echo "$existing_keys" | grep -q "$key"; then
      echo "$key" >> "$SSH_KEY_DIR/authorized_keys"
    fi
  done
fi
  echo "$AUTHORIZED_KEYS" > $SSH_KEY_DIR/authorized_keys
}

setup_zsh() {
  echo "--- Setting up Zsh ---"
  ZSHRC="$HOME/.zshrc"
  ZSH="$HOME/.oh-my-zsh"

  wget https://gitee.com/kurayuri/shrc/raw/main/.shrc -O $HOME/.shrc
  sh -c "$(curl -fsSL https://install.ohmyz.sh/)" "" --unattended
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

  ANACONDA_INSTALL_DIR="$APP_HOME/anaconda3"
  # sed -i "1i export DEVC_ID=$DEVC_ID" $ZSHRC
  echo "export DEVC_ID='$DEVC_ID'" >> $ZSHRC
  echo "export SHELL=$(which zsh)" >> $ZSHRC
  echo "export APP_HOME='$APP_HOME'" >> $ZSHRC
  echo "export CONDA_HOME='$ANACONDA_INSTALL_DIR'" >> $ZSHRC
  echo "source ${HOME}/.shrc" >> $ZSHRC
  echo 'cni' >> $ZSHRC

  # BASHRC="$HOME/.bashrc"
  # echo "source ${HOME}/.shrc" >> $BASHRC
}

# --- Argument Parsing ---

CONDA_TYPE="miniconda"
EXEC_PARTS=()
POSITIONAL=()
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    --conda-type)
      CONDA_TYPE="$2"
      shift 2
      ;;
    -x|--exec)
      EXEC_PARTS+=("$2")
      shift 2
      ;;
    *)
      POSITIONAL+=("$1") # save positional arg
      shift
      ;;
  esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters

if [ ${#EXEC_PARTS[@]} -eq 0 ]; then
  EXEC_PARTS=("all")
fi

if [ $# -eq 0 ]; then
  echo "Require DEVC_ID."
  echo "usage: $0 DEVC_ID [--conda-type miniconda|anaconda] [-x|--exec apt|conda|ssh|zsh|all]"
  exit 1
fi

DEVC_ID=$1
APP_HOME="$HOME/Application"

echo "DEVC_ID: $DEVC_ID"
echo "Conda type: $CONDA_TYPE"
echo "Executing parts: ${EXEC_PARTS[*]}"

# --- Main Execution ---

for part in "${EXEC_PARTS[@]}"; do
  if [[ "$part" == "all" || "$part" == "apt" ]]; then
    install_apt_packages
  fi
  if [[ "$part" == "all" || "$part" == "conda" ]]; then
    install_conda
  fi
  if [[ "$part" == "all" || "$part" == "ssh" ]]; then
    setup_ssh
  fi
  if [[ "$part" == "all" || "$part" == "zsh" ]]; then
    setup_zsh
  fi
done

################################################################
# # Github CLI
# type -p curl >/dev/null || (sudo apt update && sudo apt install curl -y)
# curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
# && sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
# && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
# && sudo apt update \
# && sudo apt install gh -y

# gh auth login

