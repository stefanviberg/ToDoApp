﻿Param(
	[string] $ResourceGroupSuffix = "",
	[string] $SlotName = "Staging",
	[string] $TemplateFile = "ProdAndStage.json",
	[string] $TemplateParameterFile = "param.json",
	[string] $RepoUrl = "https://github.com/azure-appservice-samples/ToDoApp.git",
	[string] $Branch = "master"
)

# Wait for a web app deployment to finish
# Get more useful functions at https://github.com/davidebbo/AzureWebsitesSamples/blob/6780a548a523cdccd1dfd66f442a7995bbb29898/PowerShell/HelperFunctionsTest.ps1
Function WaitOnDeployment($ResourceGroupName, $SiteName) 
{ 
	Write-Host -NoNewline "Waiting until the deployment for $SiteName is done..."

	#Check if named slot is specified
	if ($SiteName -match "/$SlotName")
	{
		$resourceType = "Microsoft.Web/sites/slots/Deployments"
	}
	else
	{
		$resourceType = "Microsoft.Web/sites/Deployments"
	}

	While ($true) 
	{ 
		$deployments = Get-AzureRmResource `
						-ResourceGroupName $ResourceGroupName `
						-ResourceType $resourceType `
						-Name $SiteName `
						-ApiVersion 2015-06-01 

		if ($deployments) 
		{
			$latestDeployment = $deployments[0].Properties 
			if (-not $latestDeployment.Complete) 
			{
				Write-Host -NoNewline "."
			} 
			else
			{
				Write-Host "Complete!"
				break
			}
		} 
	} 

} 

# MAIN
$start = get-date

if (!(Test-Path ".\$TemplateFile")) 
{
	write-host "template not found" -ForegroundColor Red
}
elseif (!(Test-Path ".\$TemplateParameterFile")) 
{
	write-host "template not found" -ForegroundColor Red
}
else 
{
	if(!(Get-Module Azure) -and !(Get-Module AzureResourceManager))
	{
		Import-Module Azure
	}

	[System.Console]::Clear()


	#If resource group name is not specified, assign a random string to avoid conflicts
	if($ResourceGroupSuffix -eq "")
	{
		$ResourceGroupSuffix = [system.guid]::NewGuid().tostring().substring(0,5) + $Branch.ToLower()		
	}

	#Resource Group Properties
	$RG_Name = "ToDoApp$ResourceGroupSuffix"
	$RG_Location = "North Europe"

	#Set parameters in parameter file and save to temp.json
	(Get-Content ".\${TemplateParameterFile}" -Raw) `
		-replace "{UNIQUE}",$ResourceGroupSuffix `
		-replace "{LOCATION}",$RG_Location `
		-replace "{REPO}",$RepoUrl `
		-replace "{BRANCH}",$Branch `
		-replace "{SLOT}",$SlotName | 
			Set-Content .\temp.json
		
	Write-Host "Creating Resource Group, App Service Plan, Web Apps and SQL Database..." -ForegroundColor Green 
	try 
	{
		#Missing parameters in the parameters file, such as sqlServerAdminLogin and sqlServerAdminPassword, will be
		#prompted automatically and securely
		New-AzureRmResourceGroup -Verbose `
			-name $RG_Name `
			-location $RG_Location `
			-ErrorAction Stop
        
        New-AzureRmResourceGroupDeployment `
            -name $RG_Name.ToLower() `
            -ResourceGroupName $RG_Name.ToLower() `
            -TemplateFile ".\$TemplateFile" `
			-TemplateParameterFile ".\temp.json"
	}
	catch 
	{
    	Write-Host $Error[0] -ForegroundColor Red 
    	exit 1 
	} 

	Remove-Item .\temp.json | Out-Null

	#Wait for Kudu deployment to complete and launch the deployed web application
	If($TemplateFile -match "ProdAndStage.json")
	{
		WaitOnDeployment $RG_Name "ToDoApp${ResourceGroupSuffix}/$SlotName"
		WaitOnDeployment $RG_Name "ToDoApp${ResourceGroupSuffix}Api/$SlotName"

		Show-AzureWebsite -Name "ToDoApp$ResourceGroupSuffix" -Slot $SlotName
	}
	else
	{
		WaitOnDeployment $RG_Name "ToDoApp${ResourceGroupSuffix}"
		WaitOnDeployment $RG_Name "ToDoApp${ResourceGroupSuffix}Api"

		Show-AzureWebsite -Name "ToDoApp$ResourceGroupSuffix"
	}

	Write-Host "-----------------------------------------"  -ForegroundColor Green 
	Write-Host $file "execution done"  -ForegroundColor Green 
	[System.Console]::Beep(400,1500)
	

	$end = get-date

	write-host "Start= " $start.Hour ":" $start.Minute ":" $start.Second
	write-host "End= " $end.Hour ":" $end.Minute ":" $end.Second

	pause
}