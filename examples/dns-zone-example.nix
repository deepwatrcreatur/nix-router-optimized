# Example: DNS Zone Management with Static Hosts
# 
# This example shows how to configure static DNS records that:
# - Are committed to version control
# - Coexist with DHCP dynamic registrations
# - Generate SSH config entries automatically
# - Support CNAME aliases

{
  imports = [
    # Import the dns-zone module
    nix-router-optimized.nixosModules.dns-zone
  ];

  services.router = {
    enable = true;
    
    # DNS Zone configuration
    dnsZone = {
      enable = true;
      zoneName = "deepwatercreature.com";
      allowDynamicUpdates = true;  # DHCP can still register hosts
      
      # Static hosts that are always in DNS
      staticHosts = {
        gateway = {
          ipAddress = "10.10.10.1";
          ttl = 3600;
          aliases = [ "router" "dns" "firewall" ];
        };
        
        pve-gateway = {
          ipAddress = "10.10.11.52";
          ttl = 3600;
        };
        
        pve-lattitude = {
          ipAddress = "10.10.11.47";
          ttl = 3600;
        };
        
        pve-tomahawk = {
          ipAddress = "10.10.11.55";
          ttl = 3600;
        };
        
        pve-strix = {
          ipAddress = "10.10.11.57";
          ttl = 3600;
        };
        
        attic-cache = {
          ipAddress = "10.10.11.39";
          ttl = 3600;
          aliases = [ "cache" "nix-cache" ];
        };
        
        nixoslxc = {
          ipAddress = "10.10.11.40";
          ttl = 3600;
        };
        
        ansible = {
          ipAddress = "10.10.11.67";
          ttl = 3600;
        };
        
        rustdesk = {
          ipAddress = "10.10.11.68";
          ttl = 3600;
        };
        
        homeserver = {
          ipAddress = "10.10.11.69";
          ttl = 3600;
        };
        
        inference1 = {
          ipAddress = "10.10.11.131";
          ttl = 3600;
        };
        
        inference2 = {
          ipAddress = "10.10.11.132";
          ttl = 3600;
        };
        
        inference3 = {
          ipAddress = "10.10.11.133";
          ttl = 3600;
        };
        
        casaos = {
          ipAddress = "10.10.11.77";
          ttl = 3600;
        };
      };
      
      # Optional: Create reverse DNS zones
      reverseZone = {
        enable = true;
        networks = [
          "10.10.10.0/24"
          "10.10.11.0/24"
        ];
      };
    };
  };
  
  # The DNS zone module will automatically:
  # 1. Create Technitium zone with these static records
  # 2. Generate SSH config that uses hostnames instead of IPs
  # 3. Allow DHCP to add dynamic hosts alongside static ones
  # 4. Keep everything in version control
}
