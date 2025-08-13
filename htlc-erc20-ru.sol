pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @dev Хешированные Контракты с Временной Блокировкой (HTLC) для ERC20 токенов на Ethereum.
 *
 * Этот контракт предоставляет способ создания и управления HTLC для ERC20 токенов.
 *
 * Смотрите HashedTimelock.sol для контракта, который предоставляет те же функции
 * для нативного ETH токена.
 *
 * Протокол:
 *
 *  1) newContract(receiver, hashlock, timelock, tokenContract, amount) - 
 *      отправитель вызывает это для создания нового HTLC для данного токена (tokenContract)
 *      на указанную сумму. Возвращается 32-байтный идентификатор контракта
 *  2) withdraw(contractId, preimage) - как только получатель узнает прообраз
 *      хеша блокировки, он может получить токены с помощью этой функции
 *  3) refund() - после истечения временной блокировки и если получатель не
 *      вывел токены, отправитель / создатель HTLC может вернуть свои токены
 *      с помощью этой функции.
 */
contract HashedTimelockERC20 {
    constructor() {}

    event HTLCERC20New(
        bytes32 indexed contractId,
        address indexed sender,
        address indexed receiver,
        address tokenContract,
        uint256 amount,
        bytes32 hashlock,
        uint256 timelock
    );
    event HTLCERC20Withdraw(bytes32 indexed contractId);
    event HTLCERC20Refund(bytes32 indexed contractId);

    struct LockContract {
        address sender;         // отправитель
        address receiver;       // получатель
        address tokenContract;  // адрес контракта токена
        uint256 amount;         // количество токенов
        bytes32 hashlock;       // хеш блокировки
        uint256 timelock;       // заблокировано ДО этого времени. Единица измерения зависит от алгоритма консенсуса. PoA, PoA и IBFT используют секунды. Но Quorum Raft использует наносекунды
        bool withdrawn;         // выведено ли
        bool refunded;          // возвращено ли
        bytes32 preimage;       // прообраз
    }

    modifier tokensTransferable(
        address _token,
        address _sender,
        uint256 _amount
    ) {
        require(_amount > 0, "количество токенов должно быть > 0");
        require(
            ERC20(_token).allowance(_sender, address(this)) >= _amount,
            "разрешенная сумма токенов должна быть >= количества"
        );
        _;
    }
    
    modifier futureTimelock(uint256 _time) {
        // единственное требование - время блокировки должно быть после времени последнего блока (сейчас).
        require(_time > block.timestamp, "время блокировки должно быть в будущем");
        _;
    }
    
    modifier contractExists(bytes32 _contractId) {
        require(haveContract(_contractId), "контракт с таким ID не существует");
        _;
    }
    
    modifier hashlockMatches(bytes32 _contractId, bytes32 _x) {
        require(
            contracts[_contractId].hashlock == sha256(abi.encodePacked(_x)),
            "хеш блокировки не совпадает"
        );
        _;
    }
    
    modifier withdrawable(bytes32 _contractId) {
        require(
            contracts[_contractId].receiver == msg.sender,
            "вывод доступен только получателю"
        );
        require(
            contracts[_contractId].withdrawn == false,
            "токены уже выведены"
        );
        // если мы хотим запретить вывод после истечения времени, раскомментируйте следующую строку
        // require(contracts[_contractId].timelock > now, "время блокировки должно быть в будущем");
        _;
    }
    
    modifier refundable(bytes32 _contractId) {
        require(
            contracts[_contractId].sender == msg.sender,
            "возврат доступен только отправителю"
        );
        require(
            contracts[_contractId].refunded == false,
            "токены уже возвращены"
        );
        require(
            contracts[_contractId].withdrawn == false,
            "токены уже выведены"
        );
        require(
            contracts[_contractId].timelock <= block.timestamp,
            "время блокировки еще не истекло"
        );
        _;
    }

    mapping(bytes32 => LockContract) contracts;

    /**
     * @dev Отправитель / Плательщик устанавливает новый контракт с хешированной временной блокировкой,
     * депонируя средства и указывая получателя и условия.
     *
     * ПРИМЕЧАНИЕ: _receiver должен сначала вызвать approve() на контракте токена. 
     *             Смотрите проверку allowance в модификаторе tokensTransferable.

     * @param _receiver Получатель токенов.
     * @param _hashlock SHA-256 хеш блокировки.
     * @param _timelock Время истечения блокировки в секундах UNIX эпохи. 
     *                  Возврат средств можно сделать после этого времени.
     * @param _tokenContract Адрес контракта ERC20 токена.
     * @param _amount Количество токенов для блокировки.
     * @return contractId Идентификатор нового HTLC. Он нужен для последующих 
     *                    вызовов.
     */
    function newContract(
        address _receiver,
        bytes32 _hashlock,
        uint256 _timelock,
        address _tokenContract,
        uint256 _amount
    )
        external
        tokensTransferable(_tokenContract, msg.sender, _amount)
        futureTimelock(_timelock)
        returns (bytes32 contractId)
    {
        contractId = sha256(
            abi.encodePacked(
                msg.sender,
                _receiver,
                _tokenContract,
                _amount,
                _hashlock,
                _timelock
            )
        );

        // Отклонить, если контракт с теми же параметрами уже существует. 
        // Отправитель должен изменить один из этих параметров (желательно предоставить
        // другой _hashlock).
        if (haveContract(contractId)) revert();

        // Этот контракт становится временным владельцем токенов
        if (
            !ERC20(_tokenContract).transferFrom(
                msg.sender,
                address(this),
                _amount
            )
        ) revert();

        contracts[contractId] = LockContract(
            msg.sender,
            _receiver,
            _tokenContract,
            _amount,
            _hashlock,
            _timelock,
            false,
            false,
            0x0
        );

        emit HTLCERC20New(
            contractId,
            msg.sender,
            _receiver,
            _tokenContract,
            _amount,
            _hashlock,
            _timelock
        );
    }

    /**
     * @dev Вызывается получателем, как только он узнает прообраз хеша блокировки.
     * Это передаст владение заблокированными токенами на его адрес.
     *
     * @param _contractId Идентификатор HTLC.
     * @param _preimage sha256(_preimage) должен быть равен хешу блокировки контракта.
     * @return bool true в случае успеха
     */
    function withdraw(
        bytes32 _contractId,
        bytes32 _preimage
    )
        external
        contractExists(_contractId)
        hashlockMatches(_contractId, _preimage)
        withdrawable(_contractId)
        returns (bool)
    {
        LockContract storage c = contracts[_contractId];
        c.preimage = _preimage;
        c.withdrawn = true;
        ERC20(c.tokenContract).transfer(c.receiver, c.amount);
        emit HTLCERC20Withdraw(_contractId);
        return true;
    }

    /**
     * @dev Вызывается отправителем, если не было вывода И истекла временная блокировка.
     * Это восстановит владение токенами отправителю.
     *
     * @param _contractId Идентификатор HTLC для возврата.
     * @return bool true в случае успеха
     */
    function refund(
        bytes32 _contractId
    )
        external
        contractExists(_contractId)
        refundable(_contractId)
        returns (bool)
    {
        LockContract storage c = contracts[_contractId];
        c.refunded = true;
        ERC20(c.tokenContract).transfer(c.sender, c.amount);
        emit HTLCERC20Refund(_contractId);
        return true;
    }

    /**
     * @dev Получить детали контракта.
     * @param _contractId Идентификатор HTLC контракта
     */
    function getContract(
        bytes32 _contractId
    )
        public
        view
        returns (
            address sender,
            address receiver,
            address tokenContract,
            uint256 amount,
            bytes32 hashlock,
            uint256 timelock,
            bool withdrawn,
            bool refunded,
            bytes32 preimage
        )
    {
        if (haveContract(_contractId) == false)
            return (
                address(0),
                address(0),
                address(0),
                0,
                0,
                0,
                false,
                false,
                0
            );
        LockContract storage c = contracts[_contractId];
        return (
            c.sender,
            c.receiver,
            c.tokenContract,
            c.amount,
            c.hashlock,
            c.timelock,
            c.withdrawn,
            c.refunded,
            c.preimage
        );
    }

    /**
     * @dev Существует ли контракт с идентификатором _contractId.
     * @param _contractId Идентификатор в маппинге контрактов.
     */
    function haveContract(
        bytes32 _contractId
    ) internal view returns (bool exists) {
        exists = (contracts[_contractId].sender != address(0));
    }
}