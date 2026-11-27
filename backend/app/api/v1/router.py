from fastapi import APIRouter

from app.api.v1 import auth, checkins, foods, logs, profile, recipes, weights

api_router = APIRouter()
api_router.include_router(auth.router)
api_router.include_router(profile.router)
api_router.include_router(foods.router)
api_router.include_router(recipes.router)
api_router.include_router(logs.router)
api_router.include_router(weights.router)
api_router.include_router(checkins.router)
