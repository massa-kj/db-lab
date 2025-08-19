# SQLServer

## Usage notes

This repository uses the official Microsoft SQL Server Linux container.

- The default is MSSQL_PID=Developer (for development/testing only). Do not use in production.  
  For production use, switch to Express or a paid edition and comply with the license agreement.  
  [License Guide](https://www.microsoft.com/ja-jp/sql-server/sql-server-2022-pricing)
- The [ACCEPT_EULA=Y](https://learn.microsoft.com/en-us/sql/linux/sql-server-linux-configure-environment-variables?view=sql-server-ver17) variable is set at startup. This means you are considered to have accepted the Microsoft SQL Server EULA.  
  [Configure SQL Server settings with environment variables on Linux](https://learn.microsoft.com/en-us/sql/linux/sql-server-linux-configure-environment-variables?view=sql-server-ver17)
- This repository only provides configuration/scripts and does not take responsibility for support or maintenance. Please refer to Microsoft documentation/support.  
  [Configure and customize SQL Server Linux containers](https://learn.microsoft.com/en-us/sql/linux/sql-server-linux-docker-container-configure?view=sql-server-ver17&pivots=cs1-bash)

