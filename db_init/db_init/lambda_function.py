import boto3
import os
import pg8000

connection = None
def get_connection():
    try:
        print("Connecting to database")
        client = boto3.client("rds")
        DBEndPoint = os.environ.get("DB_HOST")
        DBUserName = os.environ.get("DB_USER", "test")
        password = client.generate_db_auth_token(
            DBHostname=DBEndPoint, Port=5432, DBUsername = DBUserName
        )
        conn = pg8000.connect(
            host=DBEndPoint,
            user=DBUserName,
            password=password,
            ssl={"sslmode": "verify-full", "sslrootcert": "rds-ca-2015-root.pem"},
        )
        return conn
    except Exception as e:
        print("While connecting failed due to :{0}".format(str(e)))
        return None

def lambda_handler(event, context):
    print("Initialising Database")
    global connection
    DBName = os.environ.get("APP_DB_NAME")
    try:
        if connection is None:
            print("No existing connection, connecting..")
            connection = get_connection()
        if connection is None:
            print("Connection could not be established, aborting")
            return {"status": "Error", "message": "Failed"}
        print("instantiating the cursor from connection")
        cursor = connection.cursor()
        cursor.execute("CREATE TYPE severity AS ENUM('info', 'low', 'medium', 'high', 'critical', 'unknown')")
        query = "CREATE TABLE {0} (id SERIAL, timestamp_of_discovery timestamptz, severity severity, cve_or_name text, url text".format(DBName)
        print("Query:\n"+query)
        cursor.execute(query)
        results = cursor.fetchall()
        print("Results:")
        results = []
        for row in results:
            results.append(row)
            print(row)
        cursor.close
        # retry = False
        response = {"status": "Success", "results": str(results)}
        return response
    except Exception as e:
        try:
            connection.close()
        except Exception as e:
            connection = None
        print("Failed due to :{0}".format(str(e)))