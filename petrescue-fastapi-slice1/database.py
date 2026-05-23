from decouple import config
from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker, scoped_session

POSTGRES_USER = config("POSTGRES_USER")
POSTGRES_PASS = config("POSTGRES_PASS")
POSTGRES_DB = config("POSTGRES_DB")
POSTGRES_HOST = config("POSTGRES_HOST")
POSTGRES_PORT = config("POSTGRES_PORT")

SQLALCHEMY_DATABASE_URL = f"postgresql+psycopg2://{POSTGRES_USER}:{POSTGRES_PASS}@{POSTGRES_HOST}:{POSTGRES_PORT}/{POSTGRES_DB}"

engine = create_engine(SQLALCHEMY_DATABASE_URL,
                       pool_size=100,
                       max_overflow=20,
                       pool_timeout=60,
                       pool_recycle=1800
                       )

session_factory = sessionmaker(autocommit=False, autoflush=False, bind=engine)

SessionLocal = scoped_session(session_factory)

Base = declarative_base()