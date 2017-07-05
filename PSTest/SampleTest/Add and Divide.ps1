param ($numerator = 1, $denominator = 2)


Write-Verbose "Divide: Numerator=$numerator, Denominator=$denominator"
$sum = $numerator + $denominator
Write-Verbose "#PSTEST# Sum=$sum"
Write-Verbose 'after'

$divide = $numerator / $denominator

@{
    Sum=$sum
    Divide=$divide
}