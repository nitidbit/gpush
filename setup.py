from setuptools import setup
import os

# Read the version from the __version__.py file
version = {}
with open(os.path.join(os.path.dirname(__file__), 'src/gpush/__version__.py')) as f:
    exec(f.read(), version)

setup(
    name='gpush',
    version=version['__version__'],
    description='Wrapper for git push that runs tests, linters, and more before pushing',
    long_description=open('README.md').read(),
    long_description_content_type='text/markdown',
    url='https://github.com/nitidbit/gpush',
    author='Nitid',
    author_email='info@nitidbit.com',
    license='MIT',
    install_requires=[
        'pyyaml',
    ],
    packages=['gpush'],
    package_dir={'': 'src'},
    classifiers=[
        'Programming Language :: Python :: 3',
        'License :: OSI Approved :: MIT License',
        'Operating System :: OS Independent',
    ],
    python_requires='>=3.8',
)
