#!/bin/bash

# Define service name and log search string
service_name="stationd"
error_string="ERROR"  # Error string to search for in PC logs
gas_string="with gas used"
vrf_error_string="Failed to Init VRF"  # New error string to search for
client_error_string="Client connection error: error while requesting node"  # Another error string to search for
balance_error_string="Error in getting sender balance : http post error: Post"  # Another error string to search for
rate_limit_error_string="rpc error: code = ResourceExhausted desc = request ratelimited"  # Rate limit error string to search for
rate_limit_blob_error="rpc error: code = ResourceExhausted desc = request ratelimited: System blob rate limit for quorum 0"  # New rate limit error string to search for
err_string="ERR"  # Error string to search for in logs
retry_transaction_string="Retrying the transaction after 10 seconds..."  # Retry transaction string to search for
verify_pod_error_string="Error in VerifyPod transaction Error"  # New VerifyPod error string to search for
restart_delay=180  # Restart delay in seconds (3 minutes)
config_file="$HOME/.tracks/config/sequencer.toml"

# List of unique RPC URLs
unique_urls=(

  "https://airchains-testnet-rpc.crouton.digital/"
  "https://airchains-rpc.sbgid.com/"
  "https://junction-testnet-rpc.nodesync.top/"
  "https://airchains-rpc.kubenode.xyz/"
)

# Function to select a random URL from the list
function select_random_url {
  local array=("$@")
  local rand_index=$(( RANDOM % ${#array[@]} ))
  echo "${array[$rand_index]}"
}

echo "Script started to monitor errors in PC logs..."
echo "by onixia"

while true; do
  # Get the last 10 lines of service logs
  logs=$(systemctl status "$service_name" --no-pager | tail -n 10)

  # Check for retry transaction string in logs
  if echo "$logs" | grep -q "$retry_transaction_string"; then
    echo "Found retry transaction string in logs, updating $config_file and restarting $service_name..."

    # Select a random unique URL
    random_url=$(select_random_url "${unique_urls[@]}")

    # Update the RPC URL in the config file
    sed -i -e "s|JunctionRPC = \"[^\"]*\"|JunctionRPC = \"$random_url\"|" "$config_file"

    systemctl restart "$service_name"
    echo "Service $service_name restarted"
    # Sleep for the restart delay
    sleep "$restart_delay"
    continue
  fi

  # Check for VerifyPod error string in logs
  if echo "$logs" | grep -q "$verify_pod_error_string"; then
    echo "Found VerifyPod error string in logs, updating $config_file and restarting $service_name..."

    # Select a random unique URL
    random_url=$(select_random_url "${unique_urls[@]}")

    # Update the RPC URL in the config file
    sed -i -e "s|JunctionRPC = \"[^\"]*\"|JunctionRPC = \"$random_url\"|" "$config_file"

    systemctl restart "$service_name"
    echo "Service $service_name restarted"
    # Sleep for the restart delay
    sleep "$restart_delay"
    continue
  fi

  # Check for errors in logs
  if echo "$logs" | grep -q "$error_string" || \
     echo "$logs" | grep -q "$vrf_error_string" || \
     echo "$logs" | grep -q "$client_error_string" || \
     echo "$logs" | grep -q "$balance_error_string" || \
     echo "$logs" | grep -q "$rate_limit_error_string" || \
     echo "$logs" | grep -q "$rate_limit_blob_error" || \
     echo "$logs" | grep -q "$err_string"; then
    echo "Found error in logs, updating $config_file and restarting $service_name..."

    # Select a random unique URL
    random_url=$(select_random_url "${unique_urls[@]}")

    # Update the RPC URL in the config file
    sed -i -e "s|JunctionRPC = \"[^\"]*\"|JunctionRPC = \"$random_url\"|" "$config_file"

    # Check for gas used string in logs
    if echo "$logs" | grep -q "$gas_string"; then
      echo "Found error and gas used in logs, stopping $service_name..."
      systemctl stop "$service_name"
      cd ~/tracks

      echo "Service $service_name stopped, starting rollback..."
      go run cmd/main.go rollback
      echo "Rollback completed, starting $service_name..."
      systemctl start "$service_name"
      echo "Service $service_name started"
    else
      # Stop the service before rollback
      systemctl stop "$service_name"
      cd ~/tracks

      echo "Starting rollback after changing RPC..."
      go run cmd/main.go rollback
      echo "Rollback completed, restarting $service_name..."

      # Restart the service
      systemctl start "$service_name"
      echo "Service $service_name started"
    fi
  fi

  # Sleep for the restart delay
  sleep "$restart_delay"
done
