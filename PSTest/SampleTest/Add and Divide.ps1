param ($numerator = 1, $denominator = 2)


Write-Verbose "Divide: Numerator=$numerator, Denominator=$denominator"
$sum = $numerator + $denominator
Write-Verbose "#PSTEST# Sum=$sum"
Write-Verbose 'after'

throw "test'error1"

$divide = $numerator / $denominator

@{
    Sum=$sum
    Divide=$divide
}