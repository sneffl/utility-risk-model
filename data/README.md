# Dataset

This project uses the **State Grid Corporation of China (SGCC) electricity
theft detection dataset**: daily meter readings for 33,840 real customers
from Jan 1, 2014 to Oct 31, 2016, each labeled `FLAG = 1` if the utility
confirmed the account for electricity theft/billing fraud.

## Citation

> Zheng, Z., Yang, Y., Niu, X., Dai, H.-N., & Zhou, Y. (2018). "Wide and Deep
> Convolutional Neural Networks for Electricity-Theft Detection to Secure
> Smart Grids." *IEEE Transactions on Industrial Informatics*, 14(4),
> 1606-1615. https://doi.org/10.1109/TII.2017.2785963

## Getting the file

The raw CSV (~140MB) is not included in this repository to keep it small.
The dataset's authors distribute it as a split zip archive from their GitHub
repository:

```
git clone https://github.com/henryRDlab/ElectricityTheftDetection.git
cd ElectricityTheftDetection
zip -s0 data.zip --out data-full.zip   # joins data.zip + data.z01 + data.z02
unzip data-full.zip                     # produces data.csv
```

Place the resulting `data.csv` at `data/data.csv` in this project, then run
`scripts/01_data_prep.R` onward.
