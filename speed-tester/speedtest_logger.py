import speedtest
import csv
import datetime
import os
import time

LOG_FILE = "speedtest_results.csv"

def run_speedtest():
    print("Initializing Speedtest...")
    st = speedtest.Speedtest()
    
    print("Finding best server...")
    st.get_best_server()
    
    print("Testing download speed...")
    download_bps = st.download()
    download_mbps = download_bps / 1_000_000
    
    print("Testing upload speed...")
    upload_bps = st.upload()
    upload_mbps = upload_bps / 1_000_000
    
    ping_ms = st.results.ping
    
    return {
        "timestamp": datetime.datetime.now().isoformat(),
        "ping_ms": round(ping_ms, 2),
        "download_mbps": round(download_mbps, 2),
        "upload_mbps": round(upload_mbps, 2)
    }

def log_results(results):
    file_exists = os.path.isfile(LOG_FILE)
    
    with open(LOG_FILE, mode='a', newline='') as csvfile:
        fieldnames = ['timestamp', 'ping_ms', 'download_mbps', 'upload_mbps']
        writer = csv.DictWriter(csvfile, fieldnames=fieldnames)
        
        if not file_exists:
            writer.writeheader()
            
        writer.writerow(results)

if __name__ == "__main__":
    SPEED_THRESHOLD_MBPS = 500.0
    MAX_RETRIES = 5
    
    for attempt in range(1, MAX_RETRIES + 1):
        try:
            if attempt > 1:
                print(f"\n--- Retrying (Attempt {attempt} of {MAX_RETRIES}) ---")
                
            results = run_speedtest()
            
            # Log and print the result for EVERY attempt
            log_results(results)
            print(f"Speedtest complete! Ping: {results['ping_ms']} ms | "
                  f"Download: {results['download_mbps']} Mbps | "
                  f"Upload: {results['upload_mbps']} Mbps")
            print(f"Results logged to {LOG_FILE}")
            
            if results['download_mbps'] >= SPEED_THRESHOLD_MBPS:
                break
            elif attempt == MAX_RETRIES:
                print(f"Warning: Download speed remained below {SPEED_THRESHOLD_MBPS} Mbps after {MAX_RETRIES} attempts.")
            else:
                print(f"Download speed ({results['download_mbps']} Mbps) is below threshold ({SPEED_THRESHOLD_MBPS} Mbps).")
                print("Waiting 10 seconds before next attempt...")
                time.sleep(10)
                
        except Exception as e:
            print(f"An error occurred during attempt {attempt}: {e}")
            if attempt == MAX_RETRIES:
                print("Max retries reached. Exiting.")
            else:
                print("Waiting 10 seconds before next attempt...")
                time.sleep(10)
