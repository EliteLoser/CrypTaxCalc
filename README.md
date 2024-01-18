# CrypTaxCalc - a Coinbase transaction log parser

Svendsen Tech's CrypTaxCalc is an open-source Coinbase transaction log parser to get the numbers you need for the tax reports.

It uses the cross-platform PowerShell framework's associated scripting language, available for macOS, Linux and Windows. You can read more about it here: https://github.com/PowerShell/PowerShell 

If you are a Windows user, you already have PowerShell 5.1 installed, and can use that to run the script.

It handles buy, sell, convert, send, receive and rewards such as Coinbase learn and APY (looks for ```Buy|Learn|Reward|Receive``` in the transaction type field). This was a great deal of work and trial and error to get right. Currently, as the year 2024 has arrived, the existing code works.

# 2024

As of January 13, 2024, it works against unaltered, downloaded CSV reports from Coinbase.com. 

It supports the following sort orders for calculations (you can choose freely in some countries, such as Norway, which sort order to use): FIFO, LIFO, HPFO and LPFO. First in, first out. Last in, first out. Highest price first out. Lowest price first out.

HPFO is presumably the financially wiser option for most.

# Known bugs!

There can be rounding errors that lead to (typically) very small amounts of assets shown as "held" at the end of the year, such as with `NEAR 0.000000000000003` for me, which is actually `0.0`.

# Screenshot

![CrypTaxCalc example](/Images/cryptaxcalc-example.png)

# Examples

Examples of use against an unaltered Coinbase transaction log as of 2023-02-03.

```
PS /home/joakim/Documents> ./CrypTaxCalc.ps1 `
    -FilePath ./Coinbase-TransactionsHistoryReport-2023-02-03-23-20-48.csv `
    -SortOrder HPFO -Year 2017

Total sum of rewards in year 2017 (taxable income): 0.00


Asset holdings at the end of year 2017:

Name Value
---- -----
LTC  3.11102331
BTC  0.02608290
ETH  1.02400397

-----------------------



PS /home/joakim/Documents> ./CrypTaxCalc.ps1 `
    -FilePath ./Coinbase-TransactionsHistoryReport-2023-02-03-23-20-48.csv `
    -SortOrder HPFO -Year 2018

Total sum of rewards in year 2018 (taxable income): 0.00


Asset holdings at the end of year 2018:

Name Value
---- -----
LTC  1.09383014
BTC  0.01461435

Sales and conversions:

Asset   Result
-----   ------
LTC   -490.730
BTC   -849.510
ETH   6032.590
-----------------------




PS /home/joakim/Documents> ./CrypTaxCalc.ps1 `
    -FilePath ./Coinbase-TransactionsHistoryReport-2023-02-03-23-20-48.csv `
    -SortOrder HPFO -Year 2019

Total sum of rewards in year 2019 (taxable income): 113.93


Distribution of income:

Name Value
---- -----
BAT  26.48
XLM  87.45

Asset holdings at the end of year 2019:

Name Value
---- -----
BTC  0.34752411
LTC  1.09383014
XLM  7762.5409668
BAT  8.10041060

-----------------------

```
# 2024 Example

```
PS /home/joakim/Documents> ./CrypTaxCalc.ps1 -FilePath ./Coinbase-2024-01-12.csv `
    -Year 2023 -SortOrder HPFO
Total sum of rewards in year 2023 (taxable income): 214.29


Distribution of income:

Name Value
---- -----
ADA  55.06
AMP  11.52
NEAR 33.10
SOL  114.61


Number of rewards/income per asset:

Name Value
---- -----
ADA  70
AMP  1
NEAR 3
SOL  158

Asset holdings at the end of year 2023:

Name Value
---- -----
AAVE 7.27496954
ADA  752.514104
AMP  5582.45614384
ETH2 0.63062113
GRT  11.14324420
NEAR 0.000000000000003
SOL  9.467628126
USDC 102.810597
XLM  2062.0153870

Sales and conversions:

Asset    Result
-----    ------
FIDA   -413.650
LTC   -2079.350
NEAR     29.660
----------------------------------------
# SUMMARY

Result of all individual sales and conversion
results (all results added up) for year 2023:
-2463.34

Negative results summed up:
-2493

Positive results summed up:
29.66


Number of sales and conversions: 3
--------------------------------------
```
