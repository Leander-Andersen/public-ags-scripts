#make the formatting look goddie goddie
write-host ""



""
write-host "Leander's PnS script"
write-host "--------------------"

#create empty hash table
$PnS = @{}

#extract the sku number/product number
$skuObject = Get-WmiObject win32_computersystem | Select-Object SystemSKUNumber

#convert the object to string
$stringSku = [string]$skuObject

#extract only the sku number from the string
$inputString = $stringSku
$skuNumber = $inputString -replace '.*SystemSKUNumber=([^}]+).*','$1'

#add the sku number to the hash table with key "produktnummer"
$PnS.Add("Produktnummer", $skuNumber)


#extract the serial number
$serialObject = Get-WmiObject win32_bios | Select-Object SerialNumber

#convert the object to string
$stringSerial = [string]$serialObject

#extract only the serial number from the string
$inputString = $stringSerial
$serialNumber = $inputString -replace '.*SerialNumber=([^}]+).*','$1'

#add the serial number to the hash table with key "serienummer
$PnS.Add("Serienummer", $serialNumber)

#extract the model number
$modelObject = Get-WmiObject win32_computersystem | Select-Object Model

#convert the object to string
$stringModel = [string]$modelObject

#extract only the model number from the string
$inputString = $stringModel
$modelNumber = $inputString -replace '.*Model=([^}]+).*','$1'

#add the model number to the hash table with key "modellnummer
$PnS.Add("Modellnummer", $modelNumber)





#write to host the hash table
write-output $PnS
