# @version =0.3.3

# @title Velodrome Finance Sugar v1
# @author stas
# @notice Methods to make Velodrome devs life easier.

# Structs

MAX_PAIRS: constant(uint256) = 1000
WEEK : constant(uint256) = 604800
LAUNCH_TS: constant(uint256) = 1654128000   ## Jun 2nd 0:00 UTC 

struct Pair:
  pair_address: address
  symbol: String[100]
  stable: bool
  total_supply: uint256

  token0: address
  token0_symbol: String[100]
  token0_decimals: uint8
  reserve0: uint256

  token1: address
  token1_symbol: String[100]
  token1_decimals: uint8
  reserve1: uint256

  gauge: address
  gauge_total_supply: uint256

  fee: address
  bribe: address
  wrapped_bribe: address

  emissions: uint256
  emissions_token: address
  emissions_token_decimals: uint8

# Our contracts / Interfaces

interface IERC20:
  def decimals() -> uint8: view
  def symbol() -> String[100]: view

interface IPairFactory:
  def allPairsLength() -> uint256: view
  def allPairs(_index: uint256) -> address: view

interface IWrappedBribeFactory:
  def oldBribeToNew(_external_bribe_addr: address) -> address: view
  def voter() -> address: view

interface IPair:
  def getReserves() -> uint256[3]: view
  def token0() -> address: view
  def token1() -> address: view
  def totalSupply() -> uint256: view
  def symbol() -> String[100]: view
  def decimals() -> uint8: view
  def stable() -> bool: view

interface IVoter:
  def _ve() -> address: view
  def factory() -> address: view
  def gauges(_pair_addr: address) -> address: view
  def external_bribes(_gauge_addr: address) -> address: view
  def internal_bribes(_gauge_addr: address) -> address: view

interface IVotingEscrow:
  def token() -> address: view

interface IGauge:
  def totalSupply() -> uint256: view
  def rewardRate(_token_addr: address) -> uint256: view

interface IWrappedExternalBribe:
  def tokenRewardsPerEpoch(_token_addr: address, _epoch_start_ts: uint256) -> uint256: view

interface IExternalBribe:
  def getPriorSupplyIndex(_epoch_end_ts: uint256) -> uint256: view
  def supplyCheckpoints(_i: uint256) -> (uint256, uint256) : view

# Vars

pair_factory: public(address)
voter: public(address)
wrapped_bribe_factory: public(address)
token: public(address)
owner: public(address)

# Methods

@external
def __init__():
  """
  @dev Sets up our contract management address
  """
  self.owner = msg.sender

@external
def setup(_voter: address, _wrapped_bribe_factory: address):
  """
  @dev Sets up our external contract addresses
  """
  assert self.owner == msg.sender, 'Not allowed!'

  voter: IVoter = IVoter(_voter)
  wrapped_bribe_factory: IWrappedBribeFactory = \
    IWrappedBribeFactory(_wrapped_bribe_factory)

  assert wrapped_bribe_factory.voter() == _voter, 'Voter mismatch!'

  self.voter = _voter
  self.pair_factory = voter.factory()
  self.token = IVotingEscrow(voter._ve()).token()
  self.wrapped_bribe_factory = _wrapped_bribe_factory

@internal
@view
def _epochStart(_epoch: uint256) -> uint256:
  """
  @notice Returns epoch start ts given epoch
  @param _n_epoch The epoch to lookup
  @return uint256 epoch_start_ts
  """ 
  return LAUNCH_TS + WEEK*(_epoch - 1)

@internal
@view
def _epochEnd(_epoch: uint256) -> uint256:
  """
  @notice Returns epoch end ts given epoch
  @param _n_epoch The epoch to lookup
  @return uint256 epoch_end_ts
  """ 
  return LAUNCH_TS + WEEK*_epoch - 1

@internal
@view
def _curEpoch() -> uint256:
  """
  @notice Returns the current epoch
  @return uint8 _n_epoch
  """ 
  return (block.timestamp - LAUNCH_TS) / WEEK + 1

@internal
@view
def _bribeByEpoch(_wrapped_bribe_addr: address, _epoch: uint256) -> uint256:
  assert _epoch > 1 and _epoch <= self._curEpoch(), 'Invalid epoch!'
  wrapped_bribe: IWrappedExternalBribe = IWrappedExternalBribe(_wrapped_bribe_addr)
  return wrapped_bribe.tokenRewardsPerEpoch(0x4200000000000000000000000000000000000042, self._epochStart(_epoch))

@internal
@view
def _voteByEpoch(_bribe_addr: address, _epoch: uint256) -> uint256:
  assert _epoch > 1 and _epoch <= self._curEpoch(), 'Invalid epoch!'
  bribe: IExternalBribe = IExternalBribe(_bribe_addr)
  return bribe.supplyCheckpoints( bribe.getPriorSupplyIndex(self._epochEnd(_epoch)) )[1]

@external
@view
def test(epoch:uint256, _address:address) -> (uint256,uint256,uint256,uint256,uint256):
  voter: IVoter = IVoter(self.voter)
  wrapped_bribe_factory: IWrappedBribeFactory = \
    IWrappedBribeFactory(self.wrapped_bribe_factory)
  token: IERC20 = IERC20(self.token)

  pair: IPair = IPair(_address)
  gauge: IGauge = IGauge(voter.gauges(_address))
  bribe_addr: address = voter.external_bribes(gauge.address)
  wrapped_bribe_addr: address = \
    wrapped_bribe_factory.oldBribeToNew(bribe_addr)

  return self._curEpoch(), self._epochEnd(epoch), self._epochStart(epoch), self._voteByEpoch(bribe_addr,epoch), self._bribeByEpoch(wrapped_bribe_addr,epoch)

@internal
@view
def _pairByAddress(_address: address) -> Pair:
  """
  @notice Returns pair data based on the address
  @param _address The address to lookup
  @return Pair struct
  """
  assert _address != empty(address), 'Invalid address!'

  voter: IVoter = IVoter(self.voter)
  wrapped_bribe_factory: IWrappedBribeFactory = \
    IWrappedBribeFactory(self.wrapped_bribe_factory)
  token: IERC20 = IERC20(self.token)

  pair: IPair = IPair(_address)
  gauge: IGauge = IGauge(voter.gauges(_address))
  bribe_addr: address = voter.external_bribes(gauge.address)
  wrapped_bribe_addr: address = \
    wrapped_bribe_factory.oldBribeToNew(bribe_addr)

  token0: IERC20 = IERC20(pair.token0())
  token1: IERC20 = IERC20(pair.token1())
  reserves: uint256[3] = pair.getReserves()

  gauge_total_supply: uint256 = 0
  emissions: uint256 = 0

  if gauge.address != empty(address):
    gauge_total_supply = gauge.totalSupply()
    emissions = gauge.rewardRate(self.token)

  return Pair({
    pair_address: _address,
    symbol: pair.symbol(),
    stable: pair.stable(),
    total_supply: pair.totalSupply(),

    token0: token0.address,
    token0_symbol: token0.symbol(),
    token0_decimals: token0.decimals(),
    reserve0: reserves[0],

    token1: token1.address,
    token1_symbol: token1.symbol(),
    token1_decimals: token1.decimals(),
    reserve1: reserves[1],

    gauge: gauge.address,
    gauge_total_supply: gauge_total_supply,

    fee: voter.internal_bribes(gauge.address),
    bribe: bribe_addr,
    wrapped_bribe: wrapped_bribe_addr,

    emissions: emissions,
    emissions_token: self.token,
    emissions_token_decimals: token.decimals()
  })

@external
@view
def pairByAddress(_address: address) -> Pair:
  """
  @notice Returns pair data based on the address
  @param _address The address to lookup
  @return Pair struct
  """
  return self._pairByAddress(_address)

@external
@view
def pairs(_limit: uint256, _offset: uint256) -> DynArray[Pair, MAX_PAIRS]:
  """
  @notice Returns a collection of pair data
  @param _limit The max amount of pairs to return
  @param _offset The amount of pairs to skip
  @return Array for Pair structs
  """
  pair_factory: IPairFactory = IPairFactory(self.pair_factory)
  count: uint256 = pair_factory.allPairsLength()

  col: DynArray[Pair, MAX_PAIRS] = empty(DynArray[Pair, MAX_PAIRS])

  for index in range(MAX_PAIRS):
    if _offset > index:
      continue

    if len(col) == _limit or index >= count:
      break

    pair_addr: address = pair_factory.allPairs(index)

    col.append(self._pairByAddress(pair_addr))

  return col

@external
@view
def pairByIndex(_index: uint256) -> Pair:
  """
  @notice Returns pair data at a specific stored index
  @param _index The index to lookup
  @return Pair struct
  """
  pair_factory: IPairFactory = IPairFactory(self.pair_factory)

  return self._pairByAddress(pair_factory.allPairs(_index))
