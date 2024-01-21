from setuptools import setup

setup(
    name='gpush',
    version='2.0.0-alpha.2',
    description='Wrapper for git push that runs tests, linters, and more before pushing',
    long_description=open('README.md').read(),
    long_description_content_type='text/markdown',
    url='https://github.com/nitidbit/gpush',
    author='Nitid',
    author_email='info@nitidbit.com',
    license='MIT',  # Replace with your license
    install_requires=[
        # List your project's dependencies here
        'pyyaml',
    ],
    #  py_modules=['gpush'],  # Replace with the name of your main script
    packages=['gpush'],
    package_dir={'': 'src'},
    #  entry_points={
    #      'console_scripts': [
    #          'gpush=gpush:start',  # Replace 'gpush:main' with your entry function
    #      ],
    #  },
    classifiers=[
        # Choose classifiers: https://pypi.org/classifiers/
        'Programming Language :: Python :: 3',
        'License :: OSI Approved :: MIT License',
        'Operating System :: OS Independent',
    ],
    python_requires='>=3.8',  # Replace with your Python version requirement
)

