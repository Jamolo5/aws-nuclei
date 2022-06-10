from crawler import __version__
from crawler.lambda_function import lambda_handler


def test_version():
    assert __version__ == '0.1.0'

def test_handler():
    result = lambda_handler('','')
    print(result)
    assert result == 200