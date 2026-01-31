
# LeadsRadar - 100-Lead Simulation Script
# Run this in PowerShell to simulate 100 leads coming in
# Usage: .\simulate_leads.ps1 -ApiKey "YOUR_KEY"

param(
    [Parameter(Mandatory=$true)]
    [string]$ApiKey
)

$authors = @("tech_guru", "startup_founder", "marketing_pro", "sales_expert", "growth_hacker")
$needs = @("CRM", "automation", "lead gen", "sales tool", "email marketing")

for ($i=1; $i -le 100; $i++) {
    $author = Get-Random -InputObject $authors
    $need = Get-Random -InputObject $needs
    $id = 1000000 + $i
    
    $body = @{
        tweet_id = "$id"
        tweet_text = "I am looking for a $need solution for my business."
        tweet_author = "$author$i"
        spam_score = (Get-Random -Minimum 0 -Maximum 20)
        estimated_value = (Get-Random -Minimum 100 -Maximum 5000)
    } | ConvertTo-Json

    Write-Host "Sending Lead $i..."
    
    Invoke-RestMethod -Uri "http://localhost:3000/api/webhooks/twitter" `
        -Method Post `
        -Headers @{ "x-api-key" = $ApiKey } `
        -Body $body `
        -ContentType "application/json"
}

Write-Host "Done! Check your dashboard."
