#requires -version 4
[CmdletBinding()]
Param(
    [Parameter(Mandatory)][Alias('CsvFilePath')][String]$FilePath,
    [Parameter(Mandatory)][Int]$Year,
    #[Parameter(Mandatory)][String]$Asset,
    [Decimal]$GainTaxPercent = 22,
    [Decimal]$LossTaxPercent = 22,
    [Parameter(Mandatory)][ValidateSet('FIFO', 'LIFO', 'HPFO', 'LPFO')][String]$SortOrder,
    [String]$Delimiter = ',',
    [Int]$HeaderLine = 8,
    [Switch]$ListUsedBuyQuantities
)

$Script:Version = '3.0.2'

$Data = @{}
#$Counter = 0
$Result = @{}

foreach ($CsvLine in Get-Content -LiteralPath $FilePath |
    Select-Object -Skip ($HeaderLine - 1) | 
    ConvertFrom-Csv -Delimiter $Delimiter |
    Where-Object {$_.Timestamp -match '\S'}) {
    $Data[([DateTime]$CsvLine.Timestamp)] = $CsvLine
    #$Data[($CsvLine.Timestamp + ', ' + ('{0:D3}' -f (++$Counter)))] = $CsvLine
}

Write-Verbose "Read CSV. Populated `$Data hash. Number of keys in data hash: $($Data.Keys.Count)"

$Result = @{}

function Invoke-TransactionParser {
    Param(
        [System.Object]$Transaction,
        [Decimal]$Quantity,
        [Decimal]$CarryOverSum = 0
    )
    Write-Verbose "Buy stack value: $($Global:SvendsenTechBuyStack[0].Value.'Quantity Transacted')"
    Write-Verbose "Complete buy stack quantities: $($Global:SvendsenTechBuyStack.Value.'Quantity Transacted' -join ', ')"
    if ($Global:SvendsenTechBuyStack[0].Value.'Quantity Transacted' -ge $Quantity) {
        Write-Verbose "The buy is -ge the (remaining) sale Quantity ($Quantity). Subtracting sale Quantity from buy stack value. Populating results hash with a sale object."
        if ($ListUsedBuyQuantities) {
            Write-Verbose "-ListUsedBuyQuantities supplied. Listing the Quantity of the buy used for this sale."
            $Result[$Transaction.Name] += @([PSCustomObject]@{
                Asset = $Global:SvendsenTechBuyStack[0].Value.Asset
                UsedQuantity = $Quantity
                TotalBuyQuantity = [Decimal]$Global:SvendsenTechBuyStack[0].Value.'Quantity Transacted'
                RemainderQuantityOfSale = 0 #$RemainderQuantityOfSale
                Rate = [Decimal]$Global:SvendsenTechBuyStack[0].Value.'Spot Price at Transaction'
                UsedPurchaseValue = [Math]::Round(([Decimal]$Global:SvendsenTechBuyStack[0].Value.'Spot Price at Transaction' * $Quantity), 2)
                TotalPurchaseValue = [Math]::Round(([Decimal]$Global:SvendsenTechBuyStack[0].Value.'Spot Price at Transaction' * [Decimal]$Global:SvendsenTechBuyStack[0].Value.'Quantity Transacted'), 2)
                Fee = [Math]::Round(([Decimal]$Global:SvendsenTechBuyStack[0].Value.'Fees and/or Spread'), 2)
                DateID = $Global:SvendsenTechBuyStack[0].Value.Timestamp
                Type = "UsedPurchase"
            })
        }
        [Decimal]$Global:SvendsenTechBuyStack[0].Value.'Quantity Transacted' = [Decimal]$Global:SvendsenTechBuyStack[0].Value.'Quantity Transacted' - $Quantity
        Write-Verbose "Remaining buy stack Quantity after sale: $($Global:SvendsenTechBuyStack[0].Value.'Quantity Transacted')"
        # If the remaining quantity is 0 and it is the last buy stack element, we
        # get warnings of a null array. Storing the value we need for calculations in the
        # returned PSCustomObject.
        $SpotPriceAtTransaction = $Global:SvendsenTechBuyStack[0].Value.'Spot Price at Transaction'
        if ([Decimal]$Global:SvendsenTechBuyStack[0].Value.'Quantity Transacted' -eq 0) {
            Write-Verbose "Buy stack Quantity is 0. Popping it from the array as it is used up."
            $Global:SvendsenTechBuyStack = $Global:SvendsenTechBuyStack | Select-Object -Skip 1
        }
        $NetGainOrLoss = [Math]::Round((([Decimal]$Transaction.Value.'Quantity Transacted' * [Decimal]$Transaction.Value.'Spot Price at Transaction' - `
                [Decimal]$Transaction.Value.'Fees and/or Spread') - (
                $Quantity * [Decimal]$SpotPriceAtTransaction + $CarryOverSum)), 2)
        if ($Transaction.Value.'Transaction Type' -ne 'Send') {
            $Result[$Transaction.Name] += @([PSCustomObject]@{
                Asset = $Transaction.Value.Asset
                Quantity = $Transaction.Value.'Quantity Transacted'
                Rate = [Decimal]$Transaction.Value.'Spot Price at Transaction'
                PurchaseValue = [Math]::Round(($Quantity * [Decimal]$SpotPriceAtTransaction + $CarryOverSum), 2)
                SellValue = [Math]::Round(([Decimal]$Transaction.Value.'Quantity Transacted' * [Decimal]$Transaction.Value.'Spot Price at Transaction'), 2)
                NetSellValue = [Math]::Round(([Decimal]$Transaction.Value.'Quantity Transacted' * [Decimal]$Transaction.Value.'Spot Price at Transaction' `
                    - [Decimal]$Transaction.Value.'Fees and/or Spread'), 2)
                Fee = [Math]::Round(([Decimal]$Transaction.Value.'Fees and/or Spread'), 2)
                NetGainOrLoss = $NetGainOrLoss
                LossTaxPercent = $LossTaxPercent
                GainTaxPercent = $GainTaxPercent
                # A bit ugly, but convenient..
                NetTax = if ($NetGainOrLoss -lt 0) {
                    [Math]::Round(($NetGainOrLoss * $LossTaxPercent / 100), 2)
                }
                elseif ($NetGainOrLoss -gt 0) {
                    [Math]::Round(($NetGainOrLoss * $GainTaxPercent / 100), 2)
                }
                else {
                    0
                }
                DateID = $Transaction.Value.Timestamp
                Type = $Transaction.Value.'Transaction Type'
            })
        }
        Write-Verbose "Complete buy stack quantities: $(
            if ($SvendsenTechBuyStack.Count -gt 0) {
                $Global:SvendsenTechBuyStack.Value.'Quantity Transacted' -join ', '
            })."
    }
    else {
        Write-Verbose "$($Transaction.Value.'Transaction Type') ($Quantity) spans over the current buy Quantity ($($Global:SvendsenTechBuyStack[0].Value.'Quantity Transacted'))."
        if ($ListUsedBuyQuantities) {
            $Result[$Transaction.Name] += @([PSCustomObject]@{
                Asset = $Global:SvendsenTechBuyStack[0].Value.Asset
                UsedQuantity = [Decimal]$Global:SvendsenTechBuyStack[0].Value.'Quantity Transacted'
                TotalBuyQuantity = [Decimal]$Global:SvendsenTechBuyStack[0].Value.'Quantity Transacted'
                RemainderQuantityOfSale = $Quantity
                Rate = [Decimal]$Global:SvendsenTechBuyStack[0].Value.'Spot Price at Transaction'
                UsedPurchaseValue = [Math]::Round(([Decimal]$Global:SvendsenTechBuyStack[0].Value.'Spot Price at Transaction' * [Decimal]$Global:SvendsenTechBuyStack[0].Value.'Quantity Transacted'), 2)
                TotalPurchaseValue = [Math]::Round(([Decimal]$Global:SvendsenTechBuyStack[0].Value.'Spot Price at Transaction' * [Decimal]$Global:SvendsenTechBuyStack[0].Value.'Quantity Transacted'), 2)
                Fee = [Math]::Round(([Decimal]$Global:SvendsenTechBuyStack[0].Value.'Fees and/or Spread'), 2)
                DateID = $Global:SvendsenTechBuyStack[0].Value.Timestamp
                Type = "UsedPurchase"
            })
        }
        # Update the quantity by subtracting the current buy stack's quantity, which in this if
        # statement is less than the quantity.
        $Quantity = $Quantity - [Decimal]$Global:SvendsenTechBuyStack[0].Value.'Quantity Transacted'
        # This is the taxable Quantity to "carry over". Can cumulate across several processed buys
        # to cover a sale.
        $CarryOverSum += ([Decimal]$Global:SvendsenTechBuyStack[0].Value.'Quantity Transacted' * `
            [Decimal]$Global:SvendsenTechBuyStack[0].Value.'Spot Price at Transaction')
        Write-Verbose "Popping out first buy stack element as it is used up. Buy stack count before: $($Global:SvendsenTechBuyStack.Count)"
        $Global:SvendsenTechBuyStack = $Global:SvendsenTechBuyStack | Select-Object -Skip 1
        Write-Verbose "Buy stack count after: $($Global:SvendsenTechBuyStack.Count)"
        Write-Verbose "Carry over sum is currently: $CarryOverSum"
        Write-Verbose "Carry over Quantity is currently: $Quantity"
        Write-Verbose "Complete buy stack quantities: $($Global:SvendsenTechBuyStack.Value.'Quantity Transacted' -join ', ')"
        if ($Quantity -gt 0) {
            Invoke-TransactionParser -Transaction $Transaction -Quantity $Quantity -CarryOverSum $CarryOverSum
        }
    }
}

# The buy stack variable has to be global. Script-scoping caused complaints about
# an optimized variable. Choosing an unlikely-already-used variable name.
#[System.Object[]] $Global:SvendsenTechBuyStack = @()
#     | Cannot overwrite variable BuyStack because the variable has been optimized. Try using the New-Variable or Set-Variable cmdlet
#| (without any aliases), or dot-source the command that you are using to set the variable.
#New-Variable -Name Buystack -Scope Global -Value ([System.Object[]] @()) # didn't work.
#
# Now that I have a function, I can avoid the global variable by passing results
# to the calling code. Keeping the now-flawed design for now.
#
# Function created to make sure we don't process buys after the sale
# as part of the stack. This dawned on me late in the process.
# This will be called once for each sale, with the corresponding
# timestamp for the sale cast to a DateTime object (ISO8601).
#
# Before this, I just sorted once, meaning purchases after the sale
# could be included in the calculations, and that means everything
# changes every year if you bought more, depending on the sort order.
# Only FIFO would have worked correctly that way.
function Get-RelevantBuyStack {
    Param(
        [Parameter(Mandatory)][DateTime]$SellDate,
        [Parameter(Mandatory)][String]$Asset
    )
    if ($SortOrder -eq 'FIFO') {
        $Global:SvendsenTechBuyStack = @($Data.GetEnumerator() |
            Where-Object {$_.Value.'Transaction Type' -match 'Buy|Learn|Reward|Receive' -and `
            [DateTime]$_.Value.'Timestamp' -le $SellDate -and $_.Value.Asset -eq $Asset} | 
            Sort-Object -Property Name)
        # To get rid of the annoying warning that the variable is never used.
        $null = $Global:SvendsenTechBuyStack
    }
    elseif ($SortOrder -eq 'LIFO') {
        $Global:SvendsenTechBuyStack = @($Data.GetEnumerator() |
            Where-Object {$_.Value.'Transaction Type' -match 'Buy|Learn|Reward|Receive' -and `
            [DateTime]$_.Value.'Timestamp' -le $SellDate -and $_.Value.Asset -eq $Asset} | 
            Sort-Object -Property Name -Descending)
    }
    elseif ($SortOrder -eq 'HPFO') {
        $Global:SvendsenTechBuyStack = @($Data.GetEnumerator() |
            Where-Object {$_.Value.'Transaction Type' -match 'Buy|Learn|Reward|Receive' -and `
            [DateTime]$_.Value.'Timestamp' -le $SellDate -and $_.Value.Asset -eq $Asset} | 
            Sort-Object -Property @{Expression = {[Decimal]$_.Value.'Spot Price at Transaction'}; Descending = $True})
    }
    elseif ($SortOrder -eq 'LPFO') {
        $Global:SvendsenTechBuyStack = @($Data.GetEnumerator() |
            Where-Object {$_.Value.'Transaction Type' -match 'Buy|Learn|Reward|Receive' -and `
            [DateTime]$_.Value.'Timestamp' -le $SellDate -and $_.Value.Asset -eq $Asset} | 
            Sort-Object -Property @{Expression = {[Decimal]$_.Value.'Spot Price at Transaction'}})
    }
    #if ($Global:SvendsenTechBuyStack.Count -eq 0) {
    #    Write-Error "No purchases found before or in this year. Aborting." -ErrorAction Stop
    #}
}
#Write-Verbose ($SvendsenTechBuyStack.GetEnumerator() | Out-String)

# The buys can be FIFO, LIFO, HPFO or LPFO, but sales are always FIFO.
# The sort on "Name" is an ISO8601 timestamp, so this is FIFO for sales.
foreach ($Asset in $Data.Values.Asset | Sort-Object -Unique) {
    foreach ($Transaction in $Data.GetEnumerator() | Sort-Object -Property Name) {
        if ($Transaction.Value.'Transaction Type' -match 'Sell|Convert|Send' -and `
          ([DateTime]$Transaction.Value.'Timestamp').Year -eq $Year `
          -and $Transaction.Value.Asset -eq $Asset) {
            Get-RelevantBuyStack -SellDate $Transaction.Value.Timestamp -Asset $Asset
            Write-Verbose "Year $Year. Processing a $($Transaction.Value.'Transaction Type'
                ) of asset $($Transaction.Value.Asset
                ). Quantity of tokens: $($Transaction.Value.'Quantity Transacted')"
            Invoke-TransactionParser -Transaction $Transaction -Quantity $Transaction.Value.'Quantity Transacted'
        }
    }
}
# Calculate rewards and Coinbase learn (income) for the specified year.
$CryptoIncome = @{}
foreach ($Transaction in $Data.Values) {
    <#Get-Content -LiteralPath $FilePath |
    Select-Object -Skip ($HeaderLine - 1) | 
    ConvertFrom-Csv -Delimiter $Delimiter |
    Where-Object {$_.Timestamp -match '\S'} | 
    Sort-Object -Property Name)#>
    if ($Transaction.'Transaction Type' -match 'Reward|Learn' -and ([DateTime]$Transaction.Timestamp).Year -eq $Year) {
        #Get-RelevantBuyStack -SellDate $Transaction.Value.Timestamp
        #Write-Verbose "Year $Year. Processing a reward. Asset: $($Transaction.Asset). Quantity of tokens: $($Transaction.'Quantity Transacted'). Money: $($Transaction.'Total (inclusive of fees and/or spread)')."
        #Invoke-TransactionParser -Transaction $Transaction -Quantity $Transaction.Value.'Quantity Transacted'
        $CryptoIncome.($Transaction.Asset) += [Decimal]$Transaction.'Total (inclusive of fees and/or spread)'
    }
}

"Total sum of rewards in year $Year (taxable income): $('{0:N2}' -f (($CryptoIncome.Values | Measure-Object -Sum).Sum))`n`n"
if ($CryptoIncome.Keys.Count -gt 0) {
    "Distribution of income:"
    $CryptoIncome.GetEnumerator() | Format-Table -AutoSize
}

# Amounts owned of each asset.
$AssetHoldings = @{}
foreach ($Transaction in $Data.Values) {
    <#Get-Content -LiteralPath $FilePath |
    Select-Object -Skip ($HeaderLine - 1) | 
    ConvertFrom-Csv -Delimiter $Delimiter |
    Where-Object {$_.Timestamp -match '\S'} | 
    Sort-Object -Property Name)#>
    if (([DateTime]$Transaction.Timestamp).Year -gt $Year) {
        continue
    }
    #Write-Verbose "Processing a $($Transaction.'Transaction Type') transaction. Asset: $($Transaction.Asset). Quantity of tokens: $($Transaction.'Quantity Transacted')."
    #Invoke-TransactionParser -Transaction $Transaction -Quantity $Transaction.Value.'Quantity Transacted'
    if ($Transaction.'Transaction Type' -match 'Buy|Reward|Receive') {
        $AssetHoldings.($Transaction.'Asset') += [Decimal]$Transaction.'Quantity Transacted'
    }
    elseif ($Transaction.'Transaction Type' -match 'Sell|Convert|Send') {
        $AssetHoldings.($Transaction.'Asset') -= [Decimal]$Transaction.'Quantity Transacted'
        if ($Transaction.'Transaction Type' -match 'Convert') {
            [Decimal]$ConvertedToQuantity, $ConvertedToAsset = ($Transaction.Notes.TrimEnd() -split '\s+')[-2,-1]
            $AssetHoldings[$ConvertedToAsset] += $ConvertedToQuantity
        }
    }
}

"Asset holdings at the end of year ${Year}:"
$AssetHoldings.GetEnumerator() | Where-Object Value -gt 0 | Format-Table -AutoSize

if (($SalesAndConversions = @($Result.Values.Where({$_.Type -match 'Sell|Convert'}))).Count -gt 0) {
    "Sales and conversions:"
    $AssetResults = @(foreach ($SaleOrConversion in $SalesAndConversions) {
        $AssetResult = $Result.Values.Where({$_.Type -match 'Sell|Convert' -and $_.Asset -eq $SaleOrConversion.Asset}) |
            ForEach-Object {[Decimal]$_.NetGainOrLoss} |
            Measure-Object -Sum | 
            Select-Object -ExpandProperty Sum
        [PSCustomObject]@{
            Asset = $SaleOrConversion.Asset
            Result = $AssetResult
        }
    })
    $AssetResults
}

"-----------------------`n"

if ($AssetResults.Count -gt 0) {
    @"
# SUMMARY`n`nResult of all individual sales and conversion
results (all results added up) for year ${Year}:
"@
    $AssetResults.Result | Measure-Object -Sum | Select-Object -ExpandProperty Sum
    "`nNumber of sales and conversions: " + $AssetResults.Count
    "-----------------------`n`n"
}

