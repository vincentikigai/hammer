# Raspberry Pi Speed Testing Tool

This tool automatically tests your internet speed and logs the results (Ping, Download, Upload) to a CSV file.

## Prerequisites

Python 3 is pre-installed on the Raspberry Pi. You will need to install the dependencies.

### Installation

1. Open your terminal on the Raspberry Pi.
2. Install `pip` if you haven't already:
   ```bash
   sudo apt update
   sudo apt install python3-pip
   ```
3. Install the required Python packages from the directory containing `requirements.txt`:
   ```bash
   pip3 install -r requirements.txt
   ```
   *Note: On modern Raspberry Pi OS, you might need to use `pip3 install -r requirements.txt --break-system-packages` or set up a virtual environment (venv).*

## Running Manually

You can test the script by running it directly:

```bash
python3 speedtest_logger.py
```

This will run the test and output the results to the terminal, and also append them to `speedtest_results.csv`.

## Scheduling with Cron

To automate the speed test (e.g., to run every hour), you can set up a cron job.

1. Open the crontab editor:
   ```bash
   crontab -e
   ```
2. Add the following line to the bottom of the file (adjust `/path/to/directory` to the actual path where you placed the script):
   ```bash
   0 * * * * cd /path/to/directory && /usr/bin/python3 speedtest_logger.py >> speedtest_cron.log 2>&1
   ```
   *This specific cron expression `0 * * * *` means it will run at the start of every hour (e.g., 1:00, 2:00, etc.). The output and any errors will be appended to `speedtest_cron.log`.*

## Viewing the Logs

The speed test results will be appended to a file called `speedtest_results.csv` in the same directory as the script. You can view the contents with:

```bash
cat speedtest_results.csv
```
