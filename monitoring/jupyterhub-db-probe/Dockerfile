FROM ubi8/python-38

EXPOSE 8080

ADD src .
RUN pip install -r requirements.txt

USER 1001
CMD ["python", "main.py"]
