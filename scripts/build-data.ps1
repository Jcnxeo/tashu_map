param(
  [Parameter(Mandatory = $true)]
  [string]$TripsCsv,
  [string]$OutputJson = "data\stations.json"
)

$ErrorActionPreference = "Stop"

Add-Type -AssemblyName Microsoft.VisualBasic

$stations = @{}
$totalTrips = 0
$validTrips = 0
$invalidRows = 0

function Ensure-Station {
  param(
    [string]$Id,
    [string]$Name,
    [string]$Gu,
    [string]$Dong,
    [string]$Address,
    [string]$LatText,
    [string]$LngText
  )

  if ([string]::IsNullOrWhiteSpace($Id)) {
    return $null
  }

  $key = $Id.Trim()
  if (-not $stations.ContainsKey($key)) {
    $stations[$key] = [ordered]@{
      id = $key
      name = $Name
      gu = $Gu
      dong = $Dong
      address = $Address
      lat = $null
      lng = $null
      rentals = 0
      returns = 0
    }
  }

  $station = $stations[$key]
  if (-not [string]::IsNullOrWhiteSpace($Name)) { $station.name = $Name }
  if (-not [string]::IsNullOrWhiteSpace($Gu)) { $station.gu = $Gu }
  if (-not [string]::IsNullOrWhiteSpace($Dong)) { $station.dong = $Dong }
  if (-not [string]::IsNullOrWhiteSpace($Address)) { $station.address = $Address }

  $lat = 0.0
  $lng = 0.0
  if ([double]::TryParse($LatText, [ref]$lat) -and [double]::TryParse($LngText, [ref]$lng)) {
    if ($lat -ge 36 -and $lat -le 37 -and $lng -ge 127 -and $lng -le 128) {
      if ($null -eq $station.lat) { $station.lat = [math]::Round($lat, 6) }
      if ($null -eq $station.lng) { $station.lng = [math]::Round($lng, 6) }
    }
  }

  return $station
}

$parser = New-Object Microsoft.VisualBasic.FileIO.TextFieldParser($TripsCsv, [System.Text.Encoding]::Default)
$parser.TextFieldType = [Microsoft.VisualBasic.FileIO.FieldType]::Delimited
$parser.SetDelimiters(",")
$parser.HasFieldsEnclosedInQuotes = $true

try {
  if (-not $parser.EndOfData) {
    [void]$parser.ReadFields()
  }

  while (-not $parser.EndOfData) {
    $fields = $parser.ReadFields()
    $totalTrips++

    if ($fields.Count -lt 17) {
      $invalidRows++
      continue
    }

    $rental = Ensure-Station `
      -Id $fields[2] `
      -Name $fields[3] `
      -LatText $fields[4] `
      -LngText $fields[5] `
      -Gu $fields[6] `
      -Dong $fields[7] `
      -Address $fields[8]

    $return = Ensure-Station `
      -Id $fields[10] `
      -Name $fields[11] `
      -LatText $fields[12] `
      -LngText $fields[13] `
      -Gu $fields[14] `
      -Dong $fields[15] `
      -Address $fields[16]

    if ($null -ne $rental) { $rental.rentals++ }
    if ($null -ne $return) { $return.returns++ }

    if ($null -ne $rental -and $null -ne $return) {
      $validTrips++
    } else {
      $invalidRows++
    }
  }
}
finally {
  $parser.Close()
}

$stationRows = @($stations.Values | Where-Object { $null -ne $_.lat -and $null -ne $_.lng } | ForEach-Object {
  $imbalance = [int]$_.returns - [int]$_.rentals
  $status = "balanced"
  if ($imbalance -ge 50) { $status = "surplus" }
  if ($imbalance -le -50) { $status = "shortage" }

  [ordered]@{
    id = $_.id
    name = $_.name
    gu = $_.gu
    dong = $_.dong
    address = $_.address
    lat = $_.lat
    lng = $_.lng
    rentals = [int]$_.rentals
    returns = [int]$_.returns
    imbalance = $imbalance
    status = $status
  }
} | Sort-Object -Property @{Expression = { [math]::Abs($_.imbalance) }; Descending = $true })

$summary = [ordered]@{
  generatedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  month = "2026-02"
  source = [ordered]@{
    trips = Split-Path -Leaf $TripsCsv
  }
  totalTrips = $totalTrips
  validTrips = $validTrips
  invalidRows = $invalidRows
  stationCount = $stationRows.Count
  surplusCount = @($stationRows | Where-Object { $_.status -eq "surplus" }).Count
  shortageCount = @($stationRows | Where-Object { $_.status -eq "shortage" }).Count
  balancedCount = @($stationRows | Where-Object { $_.status -eq "balanced" }).Count
  stations = $stationRows
}

$outputPath = Join-Path (Get-Location) $OutputJson
$outputDir = Split-Path -Parent $outputPath
New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $outputPath -Encoding UTF8

Write-Host "Wrote $($stationRows.Count) stations to $outputPath"
Write-Host "Trips: $totalTrips / Valid rows: $validTrips / Invalid rows: $invalidRows"
