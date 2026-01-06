import pandas as pd
from sqlalchemy import create_engine

# Step 1: Database connection (edit credentials)
username = "root"       # your MySQL username
password = "root"   # your MySQL password
host = "localhost"
database = "steel_project"

# Step 2: Create engine
engine = create_engine(f"mysql+pymysql://{username}:{password}@{host}/{database}")

# Step 3: Excel file
excel_file = r"C:\Users\prajw\OneDrive\Desktop\DA project\SQL\GRADE_PRODUCT_MIX - Copy.xlsx"

sheets = [
    "HEAT_MASTER",
    "GRADE_MASTER",
    "RAW_MATERIAL_LOG",
    "PROCESS_METRICS",
    "SHIFT_PERFORMANCE",
    "QUALITY_ANALYSIS",
    "PROFIT_MARGIN"
]

# Step 4: Import each sheet into MySQL
for sheet in sheets:
    df = pd.read_excel(excel_file, sheet_name=sheet)
    df.to_sql(sheet, con=engine, if_exists="replace", index=False)
    print(f"✅ Imported sheet: {sheet}")

print("\nAll sheets imported into MySQL database successfully!")
