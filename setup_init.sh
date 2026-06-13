#!/usr/bin/env bash

# Check if any log files exist
if ls *.log >/dev/null 2>&1; then
    # Delete existing log files
    rm -f *.log
    echo "Previous Log files deleted."
fi

# Making environment non-interactive
export DEBIAN_FRONTEND=noninteractive

# Check if the argument is 'rerun'
if [ "$1" != "rerun" ]; then
    if type apt >/dev/null 2>&1; then
        # Update package lists and install required packages without confirmation
        sudo apt update -y
        sudo apt install python3-venv -y
    fi
    python3 -m venv .venv
fi

source .venv/bin/activate

# Upgrade pip and install necessary packages
if [ "$1" != "rerun" ]; then
    pip install --upgrade pip
    pip install wheel setuptools
    pip install -r requirements.txt
fi

# Function to send Discord message
send_discord_message() {
    curl -H "Content-Type: application/json" -X POST -d "{\"content\":\"$1\"}" $DISCORD_WEBHOOK
}

# Function to send Telegram message
send_telegram_message() {
    curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_TOKEN/sendMessage" \
         -d chat_id="$TELEGRAM_USER_ID" \
         -d text="$1"
}

# General interface to send notifications
send_notification() {
  # check all channels
  if [ -n "$DISCORD_WEBHOOK" ]; then
      send_discord_message "$1"
  fi

  if [ -n "$TELEGRAM_TOKEN" ] && [ -n "$TELEGRAM_USER_ID" ]; then
      send_telegram_message "$1"
  fi
}

# Add this near the top of the script, after the send_notification function is defined
trap 'send_notification "🛑 The setup_init.sh script has been terminated."' EXIT

# Load environment variables
source oci.env

# Function to clean up and send notification
cleanup() {
    send_notification "🛑 Heads up! The OCI Instance Creation Script has been interrupted or stopped."
    kill $SCRIPT_PID
    exit 0
}

# Function to handle suspension (Ctrl+Z)
handle_suspend() {
    send_notification "⏸️ The OCI Instance Creation Script has been suspended."
    kill -STOP $SCRIPT_PID
    kill -STOP $$
}

# Set up traps to catch various signals
trap cleanup SIGINT SIGTERM
trap handle_suspend SIGTSTP

# Run the Python program in the background; status messages below point to the log files.
nohup python3 main.py > /dev/null 2>&1 &

# Store the PID of the background process
SCRIPT_PID=$!

# Function to check if the script is still running
is_script_running() {
    if ps -p $SCRIPT_PID > /dev/null; then
        return 0
    else
        return 1
    fi
}

print_log_destination() {
    LOG_FILE=$1
    echo "Full details: $LOG_FILE"
    if [ "$TELEGRAM_LOGS_ENABLED" = "True" ] || [ "$TELEGRAM_LOGS_ENABLED" = "true" ]; then
        echo "Telegram log forwarding is enabled. Matching logs will also be sent to your configured Telegram topic."
    fi
}

# Check for the existence of ERROR_IN_CONFIG.log after running the Python program
sleep 5  # Wait for a few seconds to allow the program to run and create the log file (if applicable)
if [ -s "ERROR_IN_CONFIG.log" ]; then
    echo "Configuration error. Check ERROR_IN_CONFIG.log for full details."
    print_log_destination "ERROR_IN_CONFIG.log"
    send_notification "😕 Uh-oh! There's an error in the config. Check ERROR_IN_CONFIG.log and give it another shot!"
elif [ -s "UNHANDLED_ERROR.log" ]; then
    echo "Unexpected setup/runtime error. Check UNHANDLED_ERROR.log for full details."
    print_log_destination "UNHANDLED_ERROR.log"
    send_notification "😱 Yikes! An unhandled exception occurred. Check UNHANDLED_ERROR.log."
elif [ -s "INSTANCE_CREATED" ]; then
    echo "Instance created or Already existing has reached Free tier limit. Check 'INSTANCE_CREATED' File"
    print_log_destination "setup_and_info.log"
    send_notification "🎊 Great news! An instance was created or we've hit the Free tier limit. Check the 'INSTANCE_CREATED' file for details!"
elif [ -s "launch_instance.log" ]; then
    echo "Script started successfully. Retry logs are being written to launch_instance.log."
    print_log_destination "launch_instance.log"
    send_notification "👍 All systems go! The script is running smoothly."
else
    echo "Couldn't find any logs waiting 60 secs before checking again"  
    sleep 60  # Wait for a 1 min to see if the file is populated
    if [ -s "ERROR_IN_CONFIG.log" ]; then
        echo "Configuration error. Check ERROR_IN_CONFIG.log for full details."
        print_log_destination "ERROR_IN_CONFIG.log"
        send_notification "😕 Uh-oh! There's an error in the config. Check ERROR_IN_CONFIG.log and give it another shot!"
    elif [ -s "UNHANDLED_ERROR.log" ]; then
        echo "Unexpected setup/runtime error. Check UNHANDLED_ERROR.log for full details."
        print_log_destination "UNHANDLED_ERROR.log"
        send_notification "😱 Yikes! An unhandled exception occurred. Check UNHANDLED_ERROR.log."
    elif [ -s "launch_instance.log" ]; then
        echo "Script started successfully. Retry logs are being written to launch_instance.log."
        print_log_destination "launch_instance.log"
        send_notification "👍 Good news! The script is up and running after a short delay."
    else
        echo "No known log file was created. Check setup_and_info.log or rerun from the project directory."
        send_notification "😱 Yikes! An unhandled exception occurred. Time to put on the detective hat!"
    fi
fi

# Monitor the script and send a message when it stops
while is_script_running; do
    sleep 60
done

if [ -s "UNHANDLED_ERROR.log" ]; then
    echo "Script stopped because of an unexpected runtime error."
    print_log_destination "UNHANDLED_ERROR.log"
    send_notification "😱 The OCI Instance Creation Script stopped because of an unexpected error. Check UNHANDLED_ERROR.log."
elif [ -s "INSTANCE_CREATED" ]; then
    echo "Script finished after creating or finding the target instance."
    echo "Full details: INSTANCE_CREATED"
    send_notification "🏁 The OCI Instance Creation Script has finished running."
else
    echo "Script finished. Check setup_and_info.log and launch_instance.log if you need details."
    send_notification "🏁 The OCI Instance Creation Script has finished running."
fi

# Deactivate the virtual environment
deactivate

# Exit the script
exit 0
