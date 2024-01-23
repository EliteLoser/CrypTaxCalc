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
    [String]$CryptoJsonFile = './crypto-json-coinmarketcap-top-100-2024-01-01_02.00.01.json',
    [String]$CurrencyJsonFile = './usd_all_currencies-2024-01-01-00-00-00.json',
    [String]$HoldingsFinalTargetCurrency = 'NOK',
    [Switch]$ListUsedBuyQuantities
)
Begin {
    $Script:Version = '3.7.0'
    $NoJson = $False
    try {
        # Simplified for starters.
        $CryptoJson = Get-Content -LiteralPath $CryptoJsonFile -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
        $CurrencyJson = Get-Content -LiteralPath $CurrencyJsonFile -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        Write-Warning ("Something failed with gathering crypto and/or currency rates from" + `
            " the specified files: '$CryptoJsonFile' and '$CurrencyJsonFile'.")
        Write-Warning "Will not perform calculations of holdings in USD and the optional other currency."
        $NoJson = $True
    }
    # Debug mode. Prevents dynamic behavior, so it's not used in prod.
    #Set-StrictMode -Version Latest

    # Version history, starting from 3.2.0 -> 3.3.0
    #v3.5.0: Add calculations to find value of crypto in USD and an optional other
            # target currency (for me 'NOK'). Add data source files as collected
            # on 2 AM GMT+2 January 1, 2024, meaning midnight 2024-01-01. And for 2023.
            # Enjoy. Oh, and I added Begin, Process and End blocks, as the CmdletBinding
            # wants. Beta warning about this new feature, but it works during testing.
    # v3.4.0: # Improve usability/accessibility of exported variables.
            # Account for the bug with $Data being manipulated in memory
            # sometimes by also exporting re-read CSV.
            # Could be a bug in PowerShell (could also have been fixed by now).
    # v3.3.1: # Fix a bug that occurred with -ListUsedBuyQuantities in use.
            # It would not correctly report sales and conversions when that was in use.
            # Now it does.
    # v3.3.0: Add the used sort order to the output.

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
}
Process {
}
End {
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
            Write-Verbose "Carry over quantity is currently: $Quantity"
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
    $CryptoIncomeCount = @{}
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
            $CryptoIncomeCount.($Transaction.Asset) += 1
        }
    }

    "Total sum of rewards in year $Year (taxable income): $('{0:N2}' -f (($CryptoIncome.Values | Measure-Object -Sum).Sum))`n`n"
    if ($CryptoIncome.Keys.Count -gt 0) {
        "Distribution of income:"
        $CryptoIncome.GetEnumerator() | Sort-Object -Property Name | Format-Table -AutoSize
    }
    if ($CryptoIncomeCount.Keys.Count -gt 0) {
        "`nNumber of rewards/income per asset:"
        $CryptoIncomeCount.GetEnumerator() | Sort-Object -Property Name | Format-Table -AutoSize
    }

    # Amounts owned of each asset.
    $AssetHoldings = @{}
    foreach ($Transaction in (#$Data.Values | Sort-Object -Property Timestamp) {
        # Something weird is going on where $Data is manipulated in memory.
        # This works around a bug, by rereading the CSV file.
        Get-Content -LiteralPath $FilePath |
        Select-Object -Skip ($HeaderLine - 1) | 
        ConvertFrom-Csv -Delimiter $Delimiter |
        Where-Object {$_.Timestamp -match '\S'} | 
        Sort-Object -Property Timestamp)) {
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
    $AssetHoldings.GetEnumerator() | Where-Object Value -gt 0 | Sort-Object -Property Name | Format-Table -AutoSize

    if ($NoJson -eq $False) {
        "BETA! Experimental feature!"
        "Data from 2024-01-01-00-00-0x UTC. As found in the repo."
        "Only the top 100 coins on Coinmarketcap are available. Zero means 'not found'."
        $AssetHoldings2 = @{}
        foreach ($Holding in $AssetHoldings.GetEnumerator() | Where-Object {$_.Value -gt 0}) {
            $UsdValue = $Holding.Value * [Decimal]($CryptoJson.data.where({$_.symbol -eq ($Holding.Name -replace 'ETH2', 'ETH')}).quote.usd.price)
            $AlternateCurrencyValue = $UsdValue * [Decimal]($CurrencyJson.where({
                $_.ToCurrency -eq $HoldingsFinalTargetCurrency}).ToAmountNumerical
            )
            $AssetHoldings2.($Holding.Name) = [PSCustomObject]@{
                Asset = $Holding.Name
                TokenCount = $Holding.Value
                USDValue = $UsdValue
                AlternateCurrencyValue = $AlternateCurrencyValue
                AlternateCurrency = $HoldingsFinalTargetCurrency
            }
        }
        $AssetHoldings2.Values | Sort-Object -Property Asset, USDValue | Format-Table -AutoSize
        $UsdSum = $AssetHoldings2.Values | Measure-Object -Property USDValue -Sum | Select-Object -ExpandProperty Sum
        $AlternateSum = $AssetHoldings2.Values | Measure-Object -Property AlternateCurrencyValue -Sum | Select-Object -ExpandProperty Sum
        "Sum in USD: {0:N2}. -- Sum in ${HoldingsFinalTargetCurrency}: {1:N2}." -f $UsdSum, $AlternateSum
        "Average $HoldingsFinalTargetCurrency value for $($AssetHoldings2.Values.Count
            ) tokens: {0:N2}" -f ($AlternateSum / $AssetHoldings2.Values.Count)
        "---------------------------------`n"

    }

    # The foreach with .GetEnumerator() works around the quirky data structure
    # that causes problems when you use -ListUsedBuyQuantities. The only difference
    # is in the exported "$SvendsenTechCoinResult" variable - the report on-screen is 
    # identical in both cases.
    $SalesAndConversions = @($Result.Values.Foreach({$_.GetEnumerator()}).Where({$_.Type -match 'Sell|Convert'}))
    if ($SalesAndConversions.Count -gt 0) {
        "Sales and conversions (sort order: $($SortOrder.ToUpper())):"
        $AssetResults = @(foreach ($SaleOrConversion in $SalesAndConversions) {
            $AssetResult = $Result.Values.Foreach({$_.GetEnumerator()}).Where(
                {$_.Type -match 'Sell|Convert' -and $_.Asset -eq $SaleOrConversion.Asset}) |
                ForEach-Object {[Decimal]$_.NetGainOrLoss} |
                Measure-Object -Sum | 
                Select-Object -ExpandProperty Sum
            [PSCustomObject]@{
                Asset = $SaleOrConversion.Asset
                Result = $AssetResult
            }
        })
        $AssetResults | Sort-Object -Property Asset
    }
    "`nNumber of sales and conversions: " + $AssetResults.Count
    "----------------------------------------`n"

    if ($AssetResults.Count -gt 0) {
        "# SUMMARY`n`nResult of all individual sales and conversion"
        "results (all results added up) for year ${Year}: " + ($AssetResults.Result | 
        Measure-Object -Sum | Select-Object -ExpandProperty Sum)
        "`nNegative results summed up: " + ($AssetResults.Result | 
            Where-Object {$_ -lt 0 } | Measure-Object -Sum | Select-Object -ExpandProperty Sum)
        "`nPositive results summed up: " + ($AssetResults.Result | 
            Where-Object {$_ -gt 0 } | Measure-Object -Sum | Select-Object -ExpandProperty Sum)
        "`n--------------------------------------`n`n"
    }

    # Debug
    $Global:SvendsenTechCoinData = $Data
    $Global:SvendsenTechCoinDataRereadCSV = Get-Content -LiteralPath $FilePath |
        Select-Object -Skip ($HeaderLine - 1) | 
        ConvertFrom-Csv -Delimiter $Delimiter |
        Where-Object {$_.Timestamp -match '\S'} | 
        Sort-Object -Property Timestamp
    $Global:SvendsenTechCoinResult = $Result.foreach({$_.GetEnumerator()})

    <#
    2023-03-21: Seeing so far inexplicable behaviour. I included sales from previous
    years, to correct a bug in the previous version of CrypTaxCalc where it
    includes all rewards, converts, receives and buys for every sale (potentially
    repeated, then, for multiple sales). I am not touching the $Data structure
    at all, but if I change from -eq $Year to -le $Year (and add logic to only
    return the specified year's sales), suddenly some of the "Quantity transacted"
    become zero or seemingly rounded. I can't make any sense of it. Not even
    touching the data structure. First thoughts are somehow reference types and
    rounding, but it is only for _some_ of the quantities... Weird.

    2023-03-22: The bug seems fixed by rereading the CSV. Somehow the $Data
    variable is manipulated in memory.

    "LIFO: 0.00440380, 0.01146855, 0.02608290, 0.33290976
    FIFO: 0.33290976, 0.02163386, 0.01021055, 0.01587235
    HPFO: 0.00000000, 0.01021055, 0.33290976, 0.01587235
    LPFO: 0.00440380, 0.33290976, 0.01461435, 0.01146855" -split "`n" |
        %{$h=@{}}{$h.($_.Split(':')[0]) = ($_ -split '[:,\s]+' | select -skip 1 |
        %{[Decimal]$_} | measure-object -sum | select -Exp sum) }{$h}
    #>

}
