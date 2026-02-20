from setuptools import setup, find_packages

setup(
    name="xray-bot",
    version="0.1.0",
    packages=find_packages(),
    install_requires=[
        "aiogram>=3.7.0",
        "asyncpg>=0.29.0",
    ],
    entry_points={
        "console_scripts": [
            "xray-bot=xray_bot.__main__:main",
        ],
    },
)
