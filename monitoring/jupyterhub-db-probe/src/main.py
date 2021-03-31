import os
import time

from prometheus_client import start_http_server, Gauge
from sqlalchemy import create_engine

DATABASE_PROBE_SUCCESS = Gauge('jupyterhub_db_probe_success', 'Whether the Jupyterhub DB probe succeded. 1 indicates a success')

def main():
    user = os.getenv("JUPYTERHUB_DB_USER", "jupyterhub")
    password = os.getenv("JUPYTERHUB_DB_PASSWORD", "secretpassword")
    host = 'jupyterhub-db.redhat-ods-applications.svc.cluster.local'
    port = 5432

    start_http_server(8080)

    while True:
        DATABASE_PROBE_SUCCESS.set(connect_to_db(user, password, host, port))
        time.sleep(30)


def connect_to_db(user, password, host, port):
    try:
        db_string = f"postgresql://{user}:{password}@{host}:{port}/jupyterhub"
        db = create_engine(db_string)
        foo = db.execute("SELECT * FROM users LIMIT 1")
        return (1)
    except:
        return (0)


if __name__ == "__main__":
    main()
