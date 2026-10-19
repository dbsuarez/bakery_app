/// Converts database/UI decimal money into exact integer centavos. All
/// financial aggregation should happen in centavos and convert back only for
/// display/model compatibility.
int toCentavos(num amount) => (amount * 100).round();

double fromCentavos(int centavos) => centavos / 100;

double sumMoney(Iterable<num> amounts) =>
    fromCentavos(amounts.fold<int>(0, (sum, value) => sum + toCentavos(value)));

double subtractMoney(num amount, num deduction) =>
    fromCentavos(toCentavos(amount) - toCentavos(deduction));
