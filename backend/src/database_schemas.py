from sqlalchemy import Column , String , Text , DateTime , ForeignKey
import uuid
from datetime import datetime
from sqlalchemy.dialects.postgresql import UUID
from .database import Base



#Example :-

# class Post(Base):
#     __tablename__ = "posts"

#     id = Column( UUID(as_uuid=True) , primary_key= True ,  default=uuid.uuid4)
#     caption = Column(Text)
#     url = Column(String , nullable=False)
#     file_type = Column(String,nullable=False)
#     file_name = Column(String , nullable=False)
#     created_at = Column(DateTime , default=datetime.utcnow)