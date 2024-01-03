# CrypTaxCalc - a Coinbase transaction log parser

Svendsen Tech's CrypTaxCalc is an open-source Coinbase transaction log parser to get the numbers you need for the tax reports.

It uses the cross-platform PowerShell framework's associated scripting language, available for macOS, Linux and Windows. You can read more about it here: https://github.com/PowerShell/PowerShell 

If you are a Windows user, you already have PowerShell 5.1 installed, and can use that to run the script.

It handles buy, sell, convert, send, receive (untested) and rewards such as Coinbase learn and APY (looks for ```Buy|Learn|Reward|Receive|Staking``` in the transaction type field). This was a great deal of work and trial and error to get right. Currently, as the year 2024 arrived, I have made some changes to the code to support different data in the report such as that it now includes EUR sales and buys. I decided to omit the "base currency", which for me is EUR (EUR is the default, but I made it a parameter, e.g. "-BaseCurrency USD" if it's different for you).

# 2024 = Work In Progress

As of February 10, 2023, it worked against unaltered, downloaded CSV reports from Coinbase.com. As of January 1st, 2024, some things have changed. The reports now apparently include other/more data than last year, because my calculations produce different numbers using the previously saved log and a newly downloaded one, but this could also be due to the errors I have revealed. I noticed several grave errors/inconsistencies in the data, such as the spot rate currency being listed as NOK, while the amount is actually obviously EUR, for some, but not all of the fields, and different for different types. Staking income has one "set" of properties/errors while buy/sell has different errors.

But this is not the case for all types of transactions - and in September it was more correct than the data from December. I tried chatting with Coinbase late on New Year's Eve, but couldn't reach a human, will try to reach them somehow. I need to make them aware of these bugs/errors in the data.

Staking income is always listed in EUR, despite the currency being listed as NOK. It's quite complex to convey exactly what is wrong. The Subtotal and Total columns sometimes use EUR and sometimes NOK (supposed to always be NOK). The "fee" column appears to always be correct for the data I have manually reviewed. It is severely flawed and unusable as a data source for a report until Coinbase fixes these bugs.

It supports the following sort orders for calculations (you can choose freely in some countries, such as Norway, which sort order to use): FIFO, LIFO, HPFO and LPFO. First in, first out. Last in, first out. Highest price first out. Lowest price first out. I am not 100 % confident about the LIFO and LPFO sort orders.

HPFO is presumably the financially wiser option for most.

# Known bugs!

I think the "LIFO" and "LPFO" sort orders need some attention.

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

