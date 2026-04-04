from pydantic import BaseModel
from uuid import UUID
from datetime import datetime


#Example :-

# class PostResponse(BaseModel):
#     id: UUID
#     caption: str | None
#     url: str
#     file_type: str
#     file_name: str
#     created_at: datetime

#     class Config:
#         orm_mode = True