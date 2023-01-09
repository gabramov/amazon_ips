#!/usr/bin/env bash
# generate-nginx-amazon-whitelist.sh
#
# Cron daily with this format:
# 0 0 * * * /usr/local/bin/amazon.sh reload &>/dev/null

# Update AMAZON_WHITELIST_CONF to point to a configuration file that is included
AMAZON_WHITELIST_CONF="/etc/nginx/conf.d/amazon-whitelist.conf"

# Update RELOAD_CMD with the command used to reload the nginx configuration
RELOAD_CMD="systemctl reload nginx"

# Check for dependencies, this process requires curl and jq:
if ! type -P curl &>/dev/null; then
  echo "ERROR: install curl to retrieve amazon IP address list"
  exit 1
elif ! type -P jq &>/dev/null; then
  echo "ERROR: install jq to parse json"
  exit 1
fi

echo "###############################################"
echo "# Nginx map variable for amazon whitelist: #"
echo "###############################################"

# Create the nginx map variable based on $remote_addr.
# NOTE: If nginx is operating behind a CDN, update this map to use a header
#       or other variable that contains the real client IP address. For example,
#       Akamai can enable the 'True-Client-IP header' to hold the real client IP
#       address, so $http_true_client_ip would be used instead of $remote_addr.
#       The RealIP module can also be used to find the correct client IP address.
echo 'geo $remote_addr $is_amazon {' | tee "$AMAZON_WHITELIST_CONF"

# Parse and format amazon address blocks:
WL_URI="https://ip-ranges.amazonaws.com/ip-ranges.json"
echo '  # amazon CIDRs' | tee -a "$AMAZON_WHITELIST_CONF"
echo "  # See: ${WL_URI}" | tee -a "$AMAZON_WHITELIST_CONF"
while read cidr; do
  printf "  %-32s %s;\n" "$cidr" "1" | tee -a "$AMAZON_WHITELIST_CONF"
done< <(curl -s "${WL_URI}" | jq '.prefixes[].ip_prefix')

WL_URI="https://ip-ranges.amazonaws.com/ip-ranges.json"
echo '  # Amazon Crawler CIDRs' | tee -a "$AMAZON_WHITELIST_CONF"
echo "  # See: ${WL_URI}" | tee -a "$AMAZON_WHITELIST_CONF"
while read cidr; do
  printf "  %-32s %s;\n" "$cidr" "1" | tee -a "$AMAZON_WHITELIST_CONF"
done< <(curl -s "${WL_URI}" | jq '.ipv6_prefixes[].ipv6_prefix')

# Close the nginx map block with a default
echo "  # Default: do not whitelist" | tee -a "$AMAZON_WHITELIST_CONF"
printf "  %-32s %s;\n" "default" "0" | tee -a "$AMAZON_WHITELIST_CONF"
echo "}" | tee -a "$AMAZON_WHITELIST_CONF"

# Reload nginx if requested
if [ -n "$1" ] && [ "$1" == "reload" ]; then
  (( EUID == 0 )) && $RELOAD_CMD || sudo $RELOAD_CMD
fi
