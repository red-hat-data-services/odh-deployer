import os
import time

from prometheus_client import start_http_server, Gauge
from sqlalchemy import create_engine

DATABASE_RESPONSE_TIME = Gauge('jupyterhub_db_response_time', 'Time taken for Jupyterhub DB to respond. Negative values indicate failures')

def main():
    user = os.getenv("JUPYTERHUB_DB_USER", "jupyterhub")
    password = os.getenv("JUPYTERHUB_DB_PASSWORD", "secretpassword")
    host = 'jupyterhub-db.redhat-ods-applications.svc.cluster.local'
    port = 5432

    start_http_server(8080)

    while True:
        DATABASE_RESPONSE_TIME.set(connect_to_db(user, password, host, port))
        time.sleep(30)


def connect_to_db(user, password, host, port):
    try:
        start_time = time.time_ns() // 1_000_000
        db_string = f"postgresql://{user}:{password}@{host}:{port}/jupyterhub"
        db = create_engine(db_string)
        foo = db.execute("SELECT * FROM users LIMIT 1")
        return ((time.time_ns() // 1_000_000) - start_time)
    except:
        return (-1)


if __name__ == "__main__":
    main()
