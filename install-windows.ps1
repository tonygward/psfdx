Remove-Item $Home\Documents\PowerShell\Modules\psfdx -Recurse -Force
Copy-Item psfdx $Home\Documents\PowerShell\Modules -Recurse -Force

Remove-Item $Home\Documents\PowerShell\Modules\psfdx-logs -Recurse -Force
Copy-Item psfdx-logs $Home\Documents\PowerShell\Modules -Recurse -Force

Remove-Item $Home\Documents\PowerShell\Modules\psfdx-development -Recurse -Force
Copy-Item psfdx-development $Home\Documents\PowerShell\Modules -Recurse -Force