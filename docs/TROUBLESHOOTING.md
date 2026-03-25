# Troubleshooting Guide

This document serves as a comprehensive guide for troubleshooting common issues encountered while using the Homelab Media Stack. Follow the steps outlined for various categories of issues.

## Common Errors
- **Error 1: Service Unavailable**  
  - **Solution:** Check if the service is running and if the firewall is allowing inbound traffic on the required ports.

- **Error 2: Connection Timeout**  
  - **Solution:** Verify that the target service is reachable and that there are no network issues. Use ping or traceroute to diagnose connectivity problems.

## Log Checking
- Logs are essential for diagnosing problems. Here are the common log locations:
  - Application Logs: `/var/log/app.log`
  - System Logs: `/var/log/syslog`
  - Service-specific Logs: Check documentation for specific log paths.

- **To Check Logs:**  
  Use the following command:  
  ```bash  
  tail -f /var/log/app.log
  ```

## Service Restart Procedures
- If a service is not functioning correctly, you can restart it using the following commands:
  - For systemd services:
    ```bash
    sudo systemctl restart [service_name]
    ```
  - For Docker containers:
    ```bash
    docker restart [container_name]
    ```

## Network Tests
- To diagnose network issues, use the following commands:
  - **Ping a host:**  
    ```bash
    ping [hostname]
    ```
  - **Check open ports:**  
    ```bash
    netstat -tuln
    ```
  - **Traceroute to a destination:**  
    ```bash
    traceroute [destination]
    ```

## VPN Debugging
- If you're facing issues with the VPN connection:
  - Check VPN configurations and ensure credentials are correct.
  - Use the following command to view VPN logs:
    ```bash
    cat /var/log/vpn.log
    ```
  - Test connectivity through the VPN:
    ```bash
    curl -I [service_url]
    ```

For further assistance, consult the full documentation or reach out to support.