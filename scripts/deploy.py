import os

from brownie import accounts, Sugar


def main():
    account = accounts.load('sugar')

    sugar = Sugar.deploy({'from': account})
    sugar.setup(
        os.getenv('VOTER_ADDRESS'),
        os.getenv('WRAPPED_BRIBE_FACTORY'),
        {'from': account}
    )

# susd_usdc = '0xd16232ad60188B68076a235c65d692090caba155'
# sugar = Sugar.deploy({'from': accounts[0]})
# sugar.setup(
#     '0x09236cfF45047DBee6B921e00704bed6D6B8Cf7e',
#     '0x7955519E14fdF498E28831F4cC06af4B8e3086A8',
#     {'from': accounts[0]}
# )

# sugar.test(14,susd_usdc)

# voter = interface.voter('0x09236cfF45047DBee6B921e00704bed6D6B8Cf7e')
# voter.weights(susd_usdc ,block_identifier=1661990399)

