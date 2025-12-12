################################################################
# # tmux
TMUX_CONF_FILE=$HOME/.tmux.conf

TMUX_CONF_STR=$(cat << 'EOF'
set -g history-limit 1048576
bind C-l send-keys C-l \; clear-history
bind C-s capture-pane -S -  \; save-buffer tmux.log
EOF
)
echo $TMUX_CONF_STR > $TMUX_CONF_FILE

################################################################
# # pip
PIP_CONF_FILE="$HOME/.config/pip/pip.conf"
mkdir -p "$(dirname $PIP_CONF_FILE)"
PIP_CONF_STR=$(cat << 'EOF'
[global]
index-url = https://pypi.tuna.tsinghua.edu.cn/simple
trusted-host = pypi.tuna.tsinghua.edu.cn
EOF
)
echo "$PIP_CONF_STR" > $PIP_CONF_FILE

################################################################