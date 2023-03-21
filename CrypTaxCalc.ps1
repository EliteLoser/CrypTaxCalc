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
        if ($Transaction.Value.'Transaction Type' -ne 'Send' -and `
            ([DateTime]$Transaction.Value.Timestamp).Year -eq $Year) {
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
        Write-Verbose "$($Transaction.Value.'Transaction Type') ($Quantity) spans over the current buy Quantity ($(
            $Global:SvendsenTechBuyStack[0].Value.'Quantity Transacted'))."
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
          ([DateTime]$Transaction.Value.'Timestamp').Year -le $Year `
          -and $Transaction.Value.Asset -eq $Asset) {
            Get-RelevantBuyStack -SellDate $Transaction.Value.Timestamp -Asset $Asset
            Write-Verbose "Year $(([DateTime]$Transaction.Value.'Timestamp').Year). Processing a $($Transaction.Value.'Transaction Type'
                ) of asset --- $($Transaction.Value.Asset
                ) ---. Quantity of tokens: $($Transaction.Value.'Quantity Transacted')"
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
foreach ($Transaction in $Data.Values | Sort-Object -Property Timestamp) {
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
        Write-Verbose ("Adding (plus) a " + $Transaction.'Transaction Type'.ToLower() + " of " + $Transaction.'Quantity Transacted' + " " + $Transaction.Asset)
        $AssetHoldings.($Transaction.'Asset') += [Decimal]$Transaction.'Quantity Transacted'
    }
    elseif ($Transaction.'Transaction Type' -match 'Sell|Convert|Send') {
        Write-Verbose ("Subtracting a " + $Transaction.'Transaction Type' + " of " + $Transaction.'Quantity Transacted' + " " + $Transaction.Asset)
        $AssetHoldings.($Transaction.'Asset') -= [Decimal]$Transaction.'Quantity Transacted'
        if ($Transaction.'Transaction Type' -match 'Convert') {
            [Decimal]$ConvertedToQuantity, $ConvertedToAsset = ($Transaction.Notes.TrimEnd() -split '\s+')[-2,-1]
            Write-Verbose ("Adding (plus) a " + $Transaction.'Transaction Type'.ToLower() + " to $ConvertedToQuantity $ConvertedToAsset")
            $AssetHoldings[$ConvertedToAsset] += $ConvertedToQuantity
        }
    }
}

"Asset holdings at the end of year ${Year}:"
$AssetHoldings.GetEnumerator() | Format-Table -AutoSize
#| Where-Object Value -gt 0 | Format-Table -AutoSize

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

$Global:CoinData = $Data
$Global:CoinResult = $Result

<#
Seeing so far inexplicable behaviour. I included sales from previous
years, to correct a bug in the previous version of CrypTaxCalc where it
includes all rewards, converts, receives and buys for every sale (potentially
repeated, then, for multiple sales). I am not touching the $Data structure
at all, but if I change from -eq $Year to -le $Year (and add logic to only
return the specified year's sales), suddenly some of the "Quantity transacted"
become zero or seemingly rounded. I can't make any sense of it. Not even
touching the data structure. First thoughts are somehow reference types and
rounding, but it is only for _some_ of the quantities... Weird.


PS /home/joakim/Documents> $CoinData.Values | Sort-Object Timestamp | select -first 20 | ft -a

Timestamp            Transaction Type Asset Quantity Transacted Spot Price Currency Spot Price at Transaction Subtotal Total (inclusive of
                                                                                                                       fees and/or spread)
---------            ---------------- ----- ------------------- ------------------- ------------------------- -------- ----------------------
2017-10-29T23:43:27Z Buy              ETH                 0.000 NOK                 2489.54                   2549.28  2650.96               
2017-11-02T05:50:56Z Buy              BTC            0.01587235 NOK                 56885.28                  902.90   938.94                
2017-11-03T23:24:53Z Buy              LTC                 1.094 NOK                 461.28                    930.44   967.53                
2017-12-14T01:03:14Z Buy              LTC            1.09383014 NOK                 2576.70                   2818.50  2930.95               
2017-12-17T09:45:56Z Buy              BTC                 0.000 NOK                 165349.11                 1896.31  1971.94               
2017-12-30T22:09:15Z Buy              BTC                 0.010 NOK                 114455.63                 3788.76  3939.95               
2017-12-30T22:17:17Z Send             BTC            0.03436041 NOK                 108594.08                                                
2018-01-17T22:20:40Z Sell             ETH            1.02400397 NOK                 8507.46                   8711.68  8581.90               
2018-01-19T16:33:54Z Sell             BTC            0.01146855 NOK                 93782.70                  1075.55  1046.80               
2018-01-22T20:35:48Z Sell             LTC            2.01719317 NOK                 1385.73                   2795.24  2753.63               
2019-05-30T15:39:26Z Learning Reward  XLM            14.1611969 NOK                 1.24                      17.56    17.56                 
2019-05-30T15:42:04Z Learning Reward  XLM            14.1416213 NOK                 1.24                      17.54    17.54                 
2019-05-30T15:44:25Z Learning Reward  XLM            14.1147743 NOK                 1.24                      17.50    17.50                 
2019-05-30T15:49:16Z Learning Reward  XLM            14.0546656 NOK                 1.24                      17.43    17.43                 
2019-05-30T15:52:34Z Learning Reward  XLM            14.0500745 NOK                 1.24                      17.42    17.42                 
2019-05-30T16:04:35Z Learning Reward  BAT            2.72441334 NOK                 3.29                      8.96     8.96                  
2019-05-30T16:06:10Z Learning Reward  BAT                 0.000 NOK                 3.26                      8.76     8.76                  
2019-05-30T16:07:02Z Learning Reward  BAT            2.68799863 NOK                 3.26                      8.76     8.76                  
2019-05-30T16:40:28Z Buy              XLM              1171.401 NOK                 1.22                      9394.12  9768.95               
2019-10-21T18:01:08Z Buy              BTC                 0.162 NOK                 75376.77                  25093.67 25467.54              

#>
