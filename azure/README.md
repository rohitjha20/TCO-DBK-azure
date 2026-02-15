# Azure Cost

The 'azure_cost' project's purpose is to help enable customers to get a full TCO of their Azure cost data into Databricks.  This then allows for using Databricks native tooling to process, vizualize, and augment the cost data with data in Databricks System Tables.

<img width="1444" height="653" alt="Screenshot 2025-11-05 at 10 58 37 AM" src="https://github.com/user-attachments/assets/611b8cf5-cf23-4c98-84a9-eab3776669fe" />

## Key Outcomes:
- Vizualize Azure cost data including infrastructure, networking, and other costs in addition to Databricks costs.
- Includes any discounts a customer might have given their enterprise agreement with Microsoft
- Cost data can be joined to other [system tables](https://learn.microsoft.com/en-us/azure/databricks/admin/system-tables/), such as [system.compute.clusters](https://learn.microsoft.com/en-us/azure/databricks/admin/system-tables/compute#cluster-table-schema)

## Deployment Steps
### Deploy Terraform to configure dependent components
Terraform is used to simplify the initial setup of dependent components that are required for this solution to work - storage account, container, external location, catalog, schema, and volume.  [Terraform](https://developer.hashicorp.com/terraform) is an open-source, infrastructure as code (IaC) tool that allows you to define and provision infrastructure in human-readable configuration files.  For additional information on Terraform best practices with Databricks, please refer to the following [documentation](https://learn.microsoft.com/en-us/azure/databricks/dev-tools/terraform/).  

The Terraform requires a pre-existing Azure Subscription Id, Databricks Workspace URL, and Resource Group.  Navigate to the [Terraform subfolder](terraform/) within the Azure solution via the command line.   Within the [terraform.tfvars file](terraform/terraform.tfvars), configure the following parameters:

```
subscription_id = "<Azure Subscription Id>"
databricks_host = "<Workspace Url>"
resource_group_name = "<Resource Group Name>"
location = "<Azure Region>"
storage_account_name = "<Globally Unique Name>"
container_name = "billing"
catalog_name = "billing"
schema_name = "azure"
```

Once configured, the Terraform is deployed with the following steps.  First, one needs to login and ensure they are using the appropriate credentials when executing the Terraform.  After executing az login, select the subscription that was configured in the above variable file.

`az login`

Initializes a working directory containing Terraform configuration files.

`terraform init`

Shows a preview of the changes Terraform will make to your infrastructure before those changes are actually applied.

`terraform plan -var-file="terraform.tfvars"`

Executes the changes proposed in a Terraform plan, provisioning or modifying infrastructure resources in the target cloud or infrastructure provider. 

`terraform apply -var-file="terraform.tfvars"`
   
Upon successful completion, a message indicating “Apply complete!” is displayed in the terminal.  The Terraform has deployed a [Storage Account](https://learn.microsoft.com/en-us/azure/storage/common/storage-account-overview), [Container](https://learn.microsoft.com/en-us/azure/storage/blobs/blob-containers-portal), [External Location](https://learn.microsoft.com/en-us/azure/databricks/connect/unity-catalog/cloud-storage/external-locations), Catalog, Schema, and Volume.  These resources are the location where the Azure billing data is exported to.

### Configure Billing Export Setup into a Storage Account
Start by accessing the [Azure portal](https://portal.azure.com/) and signing in using your Azure account credentials.  On the left-hand side, click All services and search for Cost Exports.  Click create to create a new [Cost Export](https://learn.microsoft.com/en-us/azure/cost-management-billing/costs/tutorial-improved-exports).  The Azure Cost Export functionality supports a variety of different datasets, such as Actuals, Amortized, and FOCUS data.  For this solution, select Actuals.  Once selected, configure the Cost Export with the following settings and set it to deliver the exports to the Storage Account and Container created in the prior step.
   - Type of data: Cost and usage details (actual)
   - Frequency: Daily
   - Schedule status: Active
   - File partitioning: On
   - Overwrite data: Off
   - Format: Parquet
   - Compression type: Snappy

![Cost Export Setup](screenshots/AzureCostExport.gif?raw=true)

Next, validate the files are exported to the Container as those contain the Azure cost data we need (Databricks and infra costs).  On the left-hand side, click All services and search for Storage Accounts.  Select the Storage Account created in the previous step and navigate to the Container that was also created during the previous step.

![Storage Account Navigation](screenshots/AzureStorageAccountNavigation.png?raw=true)

Once inside the Container, the folder and pathing structure should look something like the following and it should also include parquet files containing the cost data.

![Container with Cost Export Data](screenshots/AzureCostExportFiles.png?raw=true)

### Databricks Asset Bundle (DAB) Configuration to deploy jobs, pipeline, and dashboard
With cost files successfully exported on a daily basis to the configured Storage Account, it is now possible to deploy the rest of the solution within Databricks.  To facilitate this step, Databricks Asset Bundles (DABs) are used to streamline the configuration and deployment process.  For more information on DABs, please check out the following [documentation](https://learn.microsoft.com/en-us/azure/databricks/dev-tools/bundles/).

First, DAB needs to be configured so that it deploys to the correct Databricks workspace.  This is done within the [databricks.yml](https://github.com/databricks-solutions/cloud-infra-costs/blob/main/azure/databricks.yml#l40) file.  To configure the desired [target](https://learn.microsoft.com/en-us/azure/databricks/dev-tools/bundles/settings#bundle-syntax-mappings-targets), use the same workspace URL as was used in the Terraform deployment.  Optionally, one can change the name of the target.  For this example, the target is named “dev”.  Additionally, one variable, `warehouse_id`, will need to be configured.  The other variables can be left as the default values presuming the name of the Catalog, Schema, Volume Name are the same as the Terraform.

| Parameter      | Description      | Default Value      |
| ------------- | ------------- | ------------- |
| catalog | Catalog where volume and tables will be configured | `billing` |
| schema | Schema where volume and tables will be configured | `azure` |
| volume_name | Name of volume | `cost_export` |
| bronze_table_name | Name of bronze table | `actual_bronze` |
| silver_table_name | Name of silver table | `actuals_silver` |
| gold_table_name | Name of gold table | `actuals_gold` |
| volume_path | Path where file arrival trigger is listening | `/Volumes/${var.catalog}/${var.schema}/${var.volume_name}/` |
| source_file_path | Location in Volume where AutoLoader is reading Cost Export files from | `${var.volume_path}*/*/*/*/*.parquet` |
| billing_period_depth | Pipeline uses split_part to extract billing period (e.g. 20250901-20250930) from file source_file_path | `7` |
| ingestion_date_depth | Pipeline uses split_part to extract ingestion date (e.g. 202509081628) from file source_file_path | `8` |
| warehouse_id | Id of SQL warehouse that the dashboard uses | N/A - Must be specified |

Authenticate to your Databricks workspace, if you have not done so already.  For additional documentation, please refer to the following [page](https://learn.microsoft.com/en-us/azure/databricks/dev-tools/cli/authentication#m2m-auth).

`databricks auth login --host <workspace-url> --profile cloud-infra-cost`

To deploy the DAB, execute the following command:

`databricks bundle deploy --target dev --profile cloud-infra-cost`

### View Dashboard and validate Lakeflow Job
Navigate to the dashboard created and validate that data appears.

![Dashboard Screenshot](screenshots/AzureDashboardScreenshot.png?raw=true)

Navigate to the jobs page and confirm that Job is executing successfully.

![Jobs Page](screenshots/AzureJobsPage.png?raw=true)

By default, the Job’s File Arrival Trigger is disabled as the DAB is configured to be deployed with [Development Mode](https://learn.microsoft.com/en-us/azure/databricks/dev-tools/bundles/deployment-modes#development-mode) enabled.  To enable the File Arrival Trigger for production use, set [Development Mode](https://github.com/databricks-solutions/cloud-infra-costs/blob/main/azure/databricks.yml#L46) to “production”.

### (Optional) - Perform additional Job and Dashboard configurations.
The dashboard and pipeline created as part of this solution provide an excellent, quick way to get started; however, there are near infinite customizations that can be done based on individual business needs that will require further customization, such as:
- Joining to other System Tables
- Modeling out reservation costs differently
